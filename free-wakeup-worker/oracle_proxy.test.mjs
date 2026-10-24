import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
test('primary mode forwards old service requests only to the VPS',async()=>{
 const {proxyOracle}=await import('./oracle_proxy.mjs?primary');
 const urls=[],secret='test-only-secret';
 const fetcher=async(url,options)=>{
  urls.push(String(url));
  if(String(url).endsWith('/v1/capabilities'))return Response.json({primaryWrites:true});
  assert.equal(options.headers.authorization,'Bearer test-user');
  return Response.json({email:'opaque-login'});
 };
 const result=await proxyOracle(new Request('https://old/account/resolve',{method:'POST',headers:{authorization:'Bearer test-user'},body:'{"code":"123456789012"}'}),{NEURAL_PUSH_SECRET:secret},{fetch:fetcher});
 assert.equal(result.status,200);assert.equal((await result.json()).email,'opaque-login');
 assert.ok(urls.every(url=>url.startsWith('https://138.2.185.151/')));
});
test('legacy alarm plans are signed and revalidated on the VPS',async()=>{
 const {proxyOracle}=await import('./oracle_proxy.mjs?scheduled');
 const secret='test-only-secret';
 const result=await proxyOracle(new Request('https://old/nudge',{method:'POST',body:'{"fireAt":1,"eventId":"test"}'}),{NEURAL_PUSH_SECRET:secret},{scheduledUid:'owner',fetch:async(url,options)=>{
  if(String(url).endsWith('/v1/capabilities'))return Response.json({primaryWrites:true});
  assert.equal(String(url),'https://138.2.185.151/internal/legacy-wake');
  const expected=createHmac('sha256',secret).update(options.headers['x-neural-time']+'\nlegacy-wake\n'+options.body).digest('hex');
  assert.equal(options.headers['x-neural-signature'],expected);
  assert.equal(JSON.parse(options.body).uid,'owner');return Response.json({message:'ok'});
 }});
 assert.equal(result.status,200);
});
test('compatibility mode is explicit; unreachable mode never falls back to stale data',async()=>{
 const off=await import('./oracle_proxy.mjs?off'),unknown=await import('./oracle_proxy.mjs?unknown');
 const request=()=>new Request('https://old/nudge',{method:'POST',body:'{}'}),env={NEURAL_PUSH_SECRET:'test'};
 assert.equal(await off.proxyOracle(request(),env,{fetch:async()=>Response.json({primaryWrites:false})}),null);
 assert.equal((await unknown.proxyOracle(request(),env,{fetch:async()=>{throw Error('offline');}})).status,503);
});
