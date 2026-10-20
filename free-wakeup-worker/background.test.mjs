import {test} from 'node:test';
import assert from 'node:assert/strict';
import {notifyCall} from './calls.mjs';
import {checkStorage,storageStatus,freeStorageBytes} from './storage.mjs';
import {WakeRateLimiter} from './worker.mjs';
const str=stringValue=>({stringValue});
const id='a'.repeat(20);
function callFixture({uid='caller',enabled=true,old=false,invalidTime=false,state='ringing'}={}){
 let pushes=0;
 const env={FIREBASE_PROJECT_ID:'demo-test',FIREBASE_API_KEY:'public-test'};
 const fetch=async(url,options)=>{
  if(url.includes('accounts:lookup'))return Response.json({users:[{localId:uid}]});
  if(url.endsWith('/voiceCalls/'+id))return Response.json({fields:{caller:str('caller'),callee:str('recipient'),state:str(state),sourceType:str('chat'),sourceId:str('one'),createdAt:{timestampValue:invalidTime?'bad-date':new Date(Date.now()-(old?60000:1000)).toISOString()}}});
  if(url.endsWith('/chats/one'))return Response.json({fields:{members:{arrayValue:{values:['caller','recipient'].map(str)}}}});
  if(url.endsWith(':runQuery'))return Response.json([{document:{fields:{enabled:{booleanValue:enabled},token:str('fake-token')}}}]);
  if(url.endsWith('messages:send')){pushes++;const message=JSON.parse(options.body).message;assert.equal(message.data.type,state==='ended'?'voice_call_end':'voice_call');assert(!('name'in message.data));assert.equal(message.android.ttl,'45s');return Response.json({name:'sent'});}
  throw Error('unexpected');
 };
 return{env,deps:{fetch,token:async()=>'fake-access'},get pushes(){return pushes;}};
}
const callRequest=(action='ring')=>new Request('https://test/call',{method:'POST',headers:{Authorization:'Bearer fake'},body:JSON.stringify({id,action})});
test('Only the caller can send a generic opt-in background call invitation',async()=>{const f=callFixture();assert.equal((await notifyCall(callRequest(),f.env,f.deps)).status,200);assert.equal(f.pushes,1);});
for(const [label,options,status]of[['outsider',{uid:'outsider'},403],['callee cannot initiate',{uid:'recipient'},409],['expired',{old:true},409],['invalid timestamp',{invalidTime:true},409]]){
 test(label+' never sends a call push',async()=>{const f=callFixture(options);assert.equal((await notifyCall(callRequest(),f.env,f.deps)).status,status);assert.equal(f.pushes,0);});
}
test('Disabled background-call device receives no push; foreground signaling remains usable',async()=>{const f=callFixture({enabled:false});assert.equal((await notifyCall(callRequest(),f.env,f.deps)).status,200);assert.equal(f.pushes,0);});
test('A participant can cancel a finished call without including a name in the push',async()=>{const f=callFixture({uid:'recipient',state:'ended'});assert.equal((await notifyCall(callRequest('end'),f.env,f.deps)).status,200);assert.equal(f.pushes,1);});
function storageFixture(){
 const values=new Map();let queue=Promise.resolve();
 const storage={get:async k=>values.get(k),put:async(k,v)=>{if(typeof k==='object'){for(const[key,value]of Object.entries(k))values.set(key,value);}else values.set(k,v);},transaction(fn){const task=queue.then(()=>fn(storage));queue=task.then(()=>{});return task;}};
 const object=new WakeRateLimiter({storage});
 const env={FIREBASE_PROJECT_ID:'demo-test',FIREBASE_API_KEY:'public-test',WAKE_RATE:{idFromName:k=>k,get:()=>object}};
 return{values,object,env};
}
test('Monthly storage check persists aggregate size, index-inclusive sample time, and 80% warning only',async()=>{
 const f=storageFixture(),bytes=Math.ceil(freeStorageBytes*0.85);
 const report=await checkStorage(f.env,{token:async()=>'fake',fetch:async()=>Response.json({timeSeries:[{resource:{labels:{database_id:'(default)'}},points:[{interval:{endTime:new Date().toISOString()},value:{int64Value:String(bytes)}}]}]})});
 assert.equal(report.bytes,bytes);assert.equal(report.warning,true);assert.equal(f.values.get('storage-latest').bytes,bytes);assert.equal(Object.keys(f.values.get('storage-history')).length,1);
 assert(!JSON.stringify(report).includes('token'));
});
test('A missing metric fails instead of reporting empty storage',async()=>{
 const f=storageFixture();await assert.rejects(checkStorage(f.env,{token:async()=>'fake',fetch:async()=>Response.json({timeSeries:[]})}));assert.equal(f.values.get('storage-latest'),undefined);
});
test('Authenticated users receive the cached report without a second metric scan that day',async()=>{
 const f=storageFixture();let scans=0;
 const deps={token:async()=>'fake',fetch:async url=>{if(url.includes('accounts:lookup'))return Response.json({users:[{localId:'user'}]});scans++;return Response.json({timeSeries:[{points:[{interval:{endTime:new Date().toISOString()},value:{int64Value:'73981343'}}]}]});}};
 const request=()=>new Request('https://test/storage/status',{headers:{Authorization:'Bearer fake'}});
 assert.equal((await storageStatus(request(),f.env,deps)).status,200);assert.equal((await storageStatus(request(),f.env,deps)).status,200);assert.equal(scans,1);
 assert.equal((await storageStatus(new Request('https://test/storage/status'),f.env,deps)).status,401);
});
test('Transient metric failure does not fabricate zero or block recovery for a full day',async()=>{
 const f=storageFixture();let healthy=false,scans=0;
 const deps={token:async()=>'fake',fetch:async url=>{if(url.includes('accounts:lookup'))return Response.json({users:[{localId:'user'}]});scans++;return healthy?Response.json({timeSeries:[{points:[{interval:{endTime:new Date().toISOString()},value:{int64Value:'73981343'}}]}]}):new Response('',{status:503});}};
 const request=()=>new Request('https://test/storage/status',{headers:{Authorization:'Bearer fake'}});
 assert.equal((await storageStatus(request(),f.env,deps)).status,503);
 assert.equal(f.values.get('storage-latest'),undefined);
 assert.equal((await storageStatus(request(),f.env,deps)).status,503);assert.equal(scans,1);
 f.values.set('storage-last-attempt',Date.now()-24*60*60*1000-1);healthy=true;
 assert.equal((await storageStatus(request(),f.env,deps)).status,200);assert.equal(scans,2);
});
