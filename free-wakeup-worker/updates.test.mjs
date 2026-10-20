import test from 'node:test';
import assert from 'node:assert/strict';
import {privateUpdates} from './updates.mjs';
const env={GITHUB_RELEASE_TOKEN:'server-only',GITHUB_RELEASE_REPO:'owner/private',FIREBASE_PROJECT_ID:'project',FIREBASE_API_KEY:'api'};
const request=(path='/updates/latest',auth=true)=>new Request('https://worker.example'+path,{headers:auth?{Authorization:'Bearer firebase-token'}:{}});
function dependencies({allowed=true,redirect='https://release-assets.githubusercontent.com/file',login=true}={}) {
  const calls=[];
  return {calls,token:async()=>'admin-only',fetch:async(url,options={})=>{
    calls.push({url,options});
    if(url.includes('accounts:lookup')) return login?Response.json({users:[{localId:'alice'}]}):new Response('',{status:401});
    if(url.includes('/updateAccess/')) return Response.json({fields:{enabled:{booleanValue:allowed}}});
    if(url.endsWith('/config/private_app_version')) return Response.json({fields:{name:{stringValue:'1.14.32'},code:{integerValue:'2076'},assetId:{integerValue:'12'},sha256:{stringValue:'a'.repeat(64)},notes:{stringValue:'Only for members'}}});
    if(url.includes('api.github.com')) return new Response(null,{status:302,headers:{Location:redirect}});
    if(url.includes('release-assets.githubusercontent.com')) return new Response('APK',{headers:{'Content-Length':'3'}});
    throw Error('Unexpected request');
  }};
}
test('No token means no release information or upstream requests',async()=>{
  const deps=dependencies(); const result=await privateUpdates(request('/updates/latest',false),env,deps);
  assert.equal(result.status,401); assert.equal(deps.calls.length,0);
});
test('An authenticated account without admin grant cannot read metadata or APK',async()=>{
  for(const path of ['/updates/latest','/updates/apk?version=1.14.32']){
    const deps=dependencies({allowed:false}); const result=await privateUpdates(request(path),env,deps);
    assert.equal(result.status,403); assert.equal(deps.calls.length,2);
    assert.ok(!(await result.text()).includes('Only for members'));
  }
});
test('Granted metadata contains no repository or server token',async()=>{
  const result=await privateUpdates(request(),env,dependencies());
  const data=await result.json(); assert.equal(data.notes,'Only for members');
  assert.equal(data.url,'https://worker.example/updates/apk?version=1.14.32');
  assert.ok(!JSON.stringify(data).includes('server-only')); assert.ok(!JSON.stringify(data).includes('owner/private'));
  assert.equal(result.headers.get('Cache-Control'),'no-store');
});
test('APK streams through server without forwarding credentials or exposing redirect',async()=>{
  const deps=dependencies(); const result=await privateUpdates(request('/updates/apk?version=1.14.32'),env,deps);
  assert.equal(result.status,200); assert.equal(await result.text(),'APK');
  assert.equal(result.headers.get('Location'),null);
  assert.equal(result.headers.get('Cache-Control'),'private, no-store');
  assert.equal(deps.calls.at(-1).options.headers,undefined);
  assert.equal(deps.calls.at(-1).options.redirect,'manual');
  assert.equal(deps.calls.at(-2).options.headers.Authorization,'Bearer server-only');
});
test('Stale version and untrusted redirect fail closed',async()=>{
  assert.equal((await privateUpdates(request('/updates/apk?version=1.0.0'),env,dependencies())).status,409);
  const deps=dependencies({redirect:'https://attacker.example/token'});
  assert.equal((await privateUpdates(request('/updates/apk?version=1.14.32'),env,deps)).status,503);
  assert.ok(!deps.calls.some(c=>c.url.includes('attacker.example')));
});
