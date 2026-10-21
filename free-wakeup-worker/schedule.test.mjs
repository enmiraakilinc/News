import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handle,WakeRateLimiter} from './worker.mjs';
const str=stringValue=>({stringValue});
function fixture({enabled=true,member=true}={}) {
  let saved,pushes=0;
  const env={FIREBASE_PROJECT_ID:'demo',FIREBASE_API_KEY:'public',SERVICE_ACCOUNT_JSON:'unused',WAKE_RATE:{idFromName:k=>k,get:()=>({fetch:async r=>{saved=r.method==='PUT'?await r.json():null;return new Response('',{status:200});}})}};
  const fetch=async url=>{
    if(url.includes('accounts:lookup')) return Response.json({users:[{localId:'sender'}]});
    if(url.endsWith('/chats/one'))return Response.json({fields:{members:{arrayValue:{values:(member?['sender','peer']:['other','peer']).map(str)}}}});
    if(url.endsWith(':runQuery'))return Response.json([{document:{fields:{enabled:{booleanValue:enabled},deviceId:str('a'.repeat(32))}}}]);
    if(url.includes('/wakeDevices/'))return Response.json({fields:{token:str('fake-fcm-token')}});
    if(url.endsWith('messages:send')) {pushes++;return Response.json({name:'test'});}
    throw Error('unexpected');
  };
  return {env,deps:{fetch,token:async()=>'mock'},get saved(){return saved;},get pushes(){return pushes;}};
}
const request=(path,fireAt)=>new Request('https://test'+path,{method:'POST',headers:{Authorization:'Bearer test'},body:JSON.stringify({sourceKey:'chat/one',recipientUid:'peer',fireAt})});
test('Scheduling persists one bounded job without storing credentials or sending an early push',async()=>{
  const f=fixture(),at=Date.now()+60000;
  assert.equal((await handle(request('/nudge/schedule',at),f.env,f.deps)).status,200);
  assert.deepEqual(f.saved,{uid:'sender',sourceKey:'chat/one',recipientUid:'peer',fireAt:at});assert.equal(f.pushes,0);
  assert.equal((await handle(request('/nudge/cancel'),f.env,f.deps)).status,200);assert.equal(f.saved,null);
});
test('Past, overly distant or unconsented schedules are rejected',async()=>{
  for(const at of [Date.now()-1,Date.now()+25*60*60*1000]) {const f=fixture();assert.equal((await handle(request('/nudge/schedule',at),f.env,f.deps)).status,400);assert.equal(f.saved,undefined);}
  const disabled=fixture({enabled:false});assert.equal((await handle(request('/nudge/schedule',Date.now()+60000),disabled.env,disabled.deps)).status,403);
});
test('At firing time revoked consent or membership prevents sending',async()=>{
  for(const options of [{enabled:false},{member:false}]) {
    const f=fixture(options);
    const r=await handle(request('/nudge'),f.env,{...f.deps,scheduledUid:'sender'});
    assert.equal(r.status,403);assert.equal(f.pushes,0);
  }
});
test('Durable schedule stores only latest plan and cancellation clears its alarm',async()=>{
  const map=new Map();let time;
  const storage={get:async k=>map.get(k),put:async(k,v)=>map.set(k,v),delete:async k=>map.delete(k),setAlarm:async t=>{time=t;},deleteAlarm:async()=>{time=undefined;}};
  const obj=new WakeRateLimiter({storage},{});
  for(const fireAt of [123,456]) await obj.fetch(new Request('https://internal/wake-schedule',{method:'PUT',body:JSON.stringify({fireAt})}));
  assert.equal(time,456);assert.equal(map.size,1);
  await obj.fetch(new Request('https://internal/wake-schedule',{method:'DELETE'}));assert.equal(time,undefined);assert.equal(map.size,0);
});

function alarmFixture(options={},overrideFetch) {
  const f=fixture(options),values=new Map();let time;
  const storage={
    get:async k=>values.get(k),put:async(k,v)=>values.set(k,v),delete:async k=>values.delete(k),
    transaction:async fn=>fn(storage),setAlarm:async t=>{time=t;},deleteAlarm:async()=>{time=undefined;}
  };
  const deps={...f.deps,fetch:overrideFetch?(...args)=>overrideFetch(f.deps.fetch,...args):f.deps.fetch};
  const object=new WakeRateLimiter({storage},f.env,deps);
  const job={uid:'sender',recipientUid:'peer',sourceKey:'chat/one',fireAt:Date.now()-10,scheduleId:'plan-a'};
  values.set('wake-job',job);
  return{f,object,storage,values,job,get time(){return time;}};
}
test('Actual alarm callback sends a fresh wake message and clears only the accepted plan',async()=>{
  let payload;
  const a=alarmFixture({},async(base,url,options)=>{
    if(url.endsWith('messages:send'))payload=JSON.parse(options.body);
    return base(url,options);
  });
  await a.object.alarm();
  assert.equal(a.f.pushes,1);
  assert.equal(payload.message.data.type,'wake');
  assert.equal(payload.message.android.priority,'HIGH');
  assert(Math.abs(Number(payload.message.data.sentAt)-Date.now())<1000);
  assert.equal(a.values.has('wake-job'),false);
});
test('Temporary FCM failure retains the plan for automatic retry instead of losing it',async()=>{
  let failing=true;const events=[];
  const a=alarmFixture({},async(base,url,options)=>{
    if(url.endsWith('messages:send'))events.push(JSON.parse(options.body).message.data.eventId);
    if(failing&&url.endsWith('messages:send'))return new Response('',{status:503});
    return base(url,options);
  });
  await assert.rejects(a.object.alarm(),/wake_delivery_retry/);
  assert.equal(a.values.get('wake-job').scheduleId,'plan-a');
  failing=false;
  await a.object.alarm();
  assert.equal(a.f.pushes,1);assert.equal(a.values.has('wake-job'),false);
  assert.equal(events.length,2);assert.equal(events[0],events[1]);
});
test('Alarm callback does not send early, late or after recipient consent is revoked',async()=>{
  const early=alarmFixture();early.job.fireAt=Date.now()+60000;
  await early.object.alarm();assert.equal(early.f.pushes,0);assert.equal(early.time,early.job.fireAt);
  const late=alarmFixture();late.job.fireAt=Date.now()-90001;
  await late.object.alarm();assert.equal(late.f.pushes,0);assert.equal(late.values.has('wake-job'),false);
  const revoked=alarmFixture({enabled:false});
  await revoked.object.alarm();assert.equal(revoked.f.pushes,0);assert.equal(revoked.values.has('wake-job'),false);
});
test('Completing an older alarm cannot erase a newer schedule saved while delivering',async()=>{
  let a;
  a=alarmFixture({},async(base,url,options)=>{
    if(url.endsWith('messages:send'))await a.storage.put('wake-job',{...a.job,scheduleId:'plan-b',fireAt:Date.now()+60000});
    return base(url,options);
  });
  await a.object.alarm();
  assert.equal(a.f.pushes,1);assert.equal(a.values.get('wake-job').scheduleId,'plan-b');
});
