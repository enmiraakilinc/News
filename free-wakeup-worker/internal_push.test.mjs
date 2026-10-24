import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {internalPush} from './internal_push.mjs';
const secret='isolated-test-only-'.repeat(3);
const body={id:'00000000-0000-4000-8000-000000000001',message:{token:'fictional-device-token-only',data:{type:'wake',eventId:'test'},android:{priority:'HIGH',ttl:'60s',collapse_key:'wake'}}};
function request(value=body,{age=0,tamper=false}={}){
 const time=String(Date.now()-age),raw=JSON.stringify(value),signature=createHmac('sha256',secret).update(time+'\n'+raw).digest('hex');
 return new Request('https://worker/internal/push',{method:'POST',headers:{'x-neural-time':time,'x-neural-signature':tamper?'0'.repeat(64):signature},body:raw});
}
test('signed transport rejects tampering, stale requests, arbitrary notifications and replay',async()=>{
 let forwarded=0,used=false;
 const env={NEURAL_PUSH_SECRET:secret,FIREBASE_PROJECT_ID:'test',WAKE_RATE:{idFromName:n=>n,get:()=>({fetch:async()=>{const status=used?429:200;used=true;return new Response('',{status});}})}};
 const deps={token:async()=>'test-only',fetch:async()=>{forwarded++;return new Response('',{status:200});}};
 for(const input of [request(body,{tamper:true}),request(body,{age:120000})])assert.equal((await internalPush(input,env,deps)).status,401);
 assert.equal((await internalPush(request({...body,message:{...body.message,notification:{title:'not allowed'}}}),env,deps)).status,400);
 assert.equal(forwarded,0);
 assert.equal((await internalPush(request(),env,deps)).status,200);
 assert.equal((await internalPush(request(),env,deps)).status,409);
 assert.equal(forwarded,1);
});
