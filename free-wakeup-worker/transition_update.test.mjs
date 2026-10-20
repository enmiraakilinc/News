import test from 'node:test';
import assert from 'node:assert/strict';
import {transitionUpdate} from './transition_update.mjs';
const env={UPDATE_BOOTSTRAP_ENABLED:'true',GITHUB_RELEASE_TOKEN:'server-only',GITHUB_RELEASE_REPO:'owner/private',FIREBASE_PROJECT_ID:'project'};
const fields={enabled:{booleanValue:true},name:{stringValue:'1.14.32'},sha256:{stringValue:'4f562651e24c3066d6bf2b7f208f899297bae61f04e53aa200d0cb8a516a2c34'},repository:{stringValue:'owner/private'},assetId:{integerValue:'12'}};
const request=()=>new Request('https://worker.example/updates/transition/1.14.32.apk');
function deps(changes={}) {
  const calls=[];
  return {calls,token:async()=>'admin',fetch:async(url,options)=>{
    calls.push({url,options});
    if(url.includes('firestore.googleapis.com'))return Response.json({fields:{...fields,...changes}});
    if(url.includes('api.github.com'))return new Response(null,{status:302,headers:{Location:'https://release-assets.githubusercontent.com/file'}});
    if(url.includes('release-assets.githubusercontent.com'))return new Response('APK');
    throw Error('Unexpected URL');
  }};
}
test('Transition serves only pinned already-public 1.14.32 without exposing notes or redirects',async()=>{
  const d=deps();const response=await transitionUpdate(request(),env,d);
  assert.equal(response.status,200);assert.equal(await response.text(),'APK');
  assert.equal(response.headers.get('Location'),null);assert.equal(d.calls.at(-1).options.headers,undefined);
});
test('Disabled transition makes no upstream request',async()=>{
  const d=deps();assert.equal((await transitionUpdate(request(),{...env,UPDATE_BOOTSTRAP_ENABLED:'false'},d)).status,404);assert.equal(d.calls.length,0);
});
test('A newer, different hash, disabled or wrong-repository release is never public',async()=>{
  for(const change of [{name:{stringValue:'1.14.33'}},{sha256:{stringValue:'a'.repeat(64)}},{enabled:{booleanValue:false}},{repository:{stringValue:'other/repo'}}]){
    const d=deps(change);assert.equal((await transitionUpdate(request(),env,d)).status,404);
    assert.ok(!d.calls.some(c=>c.url.includes('api.github.com')));
  }
});
