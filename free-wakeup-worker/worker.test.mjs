import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handle,WakeRateLimiter} from './worker.mjs';
const str=stringValue=>({stringValue});
function fixture({member=true,enabled=true,limited=false,authenticated=true}={}) {
  const urls=[];let pushes=0;
  const env={FIREBASE_PROJECT_ID:'demo-test',FIREBASE_API_KEY:'public-test',SERVICE_ACCOUNT_JSON:'unused',WAKE_RATE:{idFromName:k=>k,get:()=>({fetch:async()=>new Response('',{status:limited?429:200})})}};
  const fetch=async(url,options)=>{
    urls.push(url);
    if(url.includes('accounts:lookup'))return Response.json({users:[{localId:'sender'}]},{status:authenticated?200:401});
    if(url.endsWith('/chats/one'))return Response.json({fields:{members:{arrayValue:{values:(member?['sender','recipient']:['other','recipient']).map(str)}}}});
    if(url.endsWith(':runQuery'))return Response.json([{document:{fields:{enabled:{booleanValue:enabled},deviceId:str('a'.repeat(32))}}}]);
    if(url.includes('/wakeDevices/'))return Response.json({fields:{token:str('fake-fcm-token')}});
    if(url.endsWith('messages:send')){pushes++;const data=JSON.parse(options.body);assert.equal(data.message.android.priority,'HIGH');assert.equal(data.message.android.ttl,'60s');return Response.json({name:'test'});}
    throw Error('Unexpected external operation');
  };
  return {env,deps:{fetch,token:async()=>'mock'},urls,get pushes(){return pushes;}};
}
const request=()=>new Request('https://test/nudge',{method:'POST',headers:{Authorization:'Bearer test'},body:JSON.stringify({sourceKey:'chat/one',recipientUid:'recipient'})});
test('Authenticated member with recipient consent can send one high-priority bounded nudge',async()=>{const f=fixture();const r=await handle(request(),f.env,f.deps);assert.equal(r.status,200);assert.equal(f.pushes,1);assert(!f.urls.some(u=>u.endsWith(':commit')));});
for(const [name,options,status] of [['outsider',{member:false},403],['recipient disabled',{enabled:false},403],['bad login',{authenticated:false},401]]) {
  test(name+' cannot trigger alarm',async()=>{const f=fixture(options);assert.equal((await handle(request(),f.env,f.deps)).status,status);assert.equal(f.pushes,0);});
}
test('Consecutive deliberate nudges have no five-minute cooldown',async()=>{const f=fixture({limited:true});assert.equal((await handle(request(),f.env,f.deps)).status,200);assert.equal((await handle(request(),f.env,f.deps)).status,200);assert.equal(f.pushes,2);});
test('Unconfigured server and missing authorization never send anything',async()=>{assert.equal((await handle(request(),{})).status,503);const f=fixture();assert.equal((await handle(new Request('https://test/nudge',{method:'POST'}),f.env,f.deps)).status,401);assert.equal(f.urls.length,0);});
test('Legacy binding remains compatible without imposing a cooldown',async()=>{
  let last,queue=Promise.resolve();
  const store={get:async()=>last,put:async(_,v)=>{last=v;},transaction(fn){const work=queue.then(()=>fn(store));queue=work.then(()=>{});return work;}};
  const limiter=new WakeRateLimiter({storage:store});
  const results=await Promise.all([limiter.fetch(new Request('https://internal',{method:'POST'})),limiter.fetch(new Request('https://internal',{method:'POST'}))]);
  assert.deepEqual(results.map(r=>r.status),[200,200]);
});
