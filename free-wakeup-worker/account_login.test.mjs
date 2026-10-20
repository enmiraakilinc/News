import {test} from 'node:test';
import assert from 'node:assert/strict';
import {resolveAccount} from './account_login.mjs';
import {WakeRateLimiter} from './worker.mjs';
const request=code=>new Request('https://test/account/resolve',{method:'POST',headers:{Authorization:'Bearer valid','CF-Connecting-IP':'test-ip'},body:JSON.stringify({code})});
function fixture({limited=false,authenticated=true,missing=false}={}) {
  const calls=[];
  const env={FIREBASE_PROJECT_ID:'demo',FIREBASE_API_KEY:'test',WAKE_RATE:{idFromName:k=>k,get:()=>({fetch:async()=>new Response('',{status:limited?429:200})})}};
  const fetch=async(url,options)=>{
    calls.push({url,options});
    if(url.includes('accounts:lookup'))return Response.json({users:[{localId:'anon-user'}]},{status:authenticated?200:401});
    return Response.json({fields:{email:{stringValue:'a'.repeat(32)+'@accounts.neural.invalid'},owner:{stringValue:'private-owner'}}},{status:missing?404:200});
  };
  return {env,calls,deps:{fetch,token:async()=>'server-token'}};
}
test('Authenticated alias lookup returns only opaque Auth login, never owner identity or tokens',async()=>{
  const f=fixture(),r=await resolveAccount(request('123456789012'),f.env,f.deps);
  assert.equal(r.status,200);assert.deepEqual(Object.keys(await r.json()),['email']);
  assert(!JSON.stringify(f.calls).includes('password'));
});
test('Unauthenticated or throttled callers cannot read alias documents',async()=>{
  for(const options of [{limited:true},{authenticated:false}]){
    const f=fixture(options),r=await resolveAccount(request('123456789012'),f.env,f.deps);
    assert([401,429].includes(r.status));assert(!f.calls.some(c=>c.url.includes('firestore')));
  }
});
test('Invalid aliases and absent documents do not expose unrelated data',async()=>{
  const f=fixture({missing:true});assert.equal((await resolveAccount(request('123456789012'),f.env,f.deps)).status,404);
  const bad=fixture();assert.equal((await resolveAccount(request('../../other'),bad.env,bad.deps)).status,400);assert.equal(bad.calls.length,0);
});
test('Atomic account resolver rate limit enforces attempts independently of nudge cooldown',async()=>{
  const map=new Map();let queue=Promise.resolve();
  const store={get:async k=>map.get(k),put:async(k,v)=>map.set(k,structuredClone(v)),transaction(fn){const p=queue.then(()=>fn(store));queue=p.then(()=>{});return p;}};
  const limiter=new WakeRateLimiter({storage:store});
  const responses=await Promise.all(Array.from({length:10},()=>limiter.fetch(new Request('https://internal/account/reserve',{method:'POST',body:JSON.stringify({limit:6})}))));
  assert.equal(responses.filter(r=>r.status===200).length,6);assert.equal(responses.filter(r=>r.status===429).length,4);
});
