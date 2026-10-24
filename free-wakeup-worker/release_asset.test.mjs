import test from 'node:test';
import assert from 'node:assert/strict';
import {streamReleaseAsset} from './release_asset.mjs';
test('repository renames use a stable numeric API identity without following arbitrary redirects',async()=>{
 let calls=0;
 const env={GITHUB_RELEASE_REPO:'old/name',GITHUB_RELEASE_REPOSITORY_ID:'1426918054',GITHUB_RELEASE_TOKEN:'test-only'};
 const result=await streamReleaseAsset(env,async(url,options)=>{
  calls++;
  if(calls===1){assert.equal(url,'https://api.github.com/repositories/1426918054/releases/assets/123');assert.equal(options.headers.Authorization,'Bearer test-only');return new Response(null,{status:302,headers:{Location:'https://release-assets.githubusercontent.com/file'}});}
  assert.equal(options.headers,undefined);return new Response(new Uint8Array([1,2,3]));
 },'123','1.14.32');
 assert.equal(result.status,200);assert.deepEqual([...new Uint8Array(await result.arrayBuffer())],[1,2,3]);
});
