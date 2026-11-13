// Sunucu kuralının otomatik sınamasıdır.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {privateUpdate} from '../src/updates.mjs';

test('private update metadata keeps the APK URL on the API origin',async()=>{
 const directory=await mkdtemp(join(tmpdir(),'neural-updates-'));
 try{
  await writeFile(join(directory,'1.16.4.apk'),'test apk');
  const store={get:async path=>path.startsWith('updateAccess/')
   ?{enabled:{booleanValue:true}}
   :{name:{stringValue:'1.16.4'},sha256:{stringValue:'a'.repeat(64)},code:{integerValue:'2085'},notes:{stringValue:'Test'}}};
  const response={writeHead(status,headers){this.status=status;this.headers=headers;},end(body){this.body=body;}};
  const requestUrl=new URL('https://updates.test/updates/latest');

  await privateUpdate(store,{uid:'test-user'},requestUrl,response,{directory});

  assert.equal(response.status,200);
  assert.equal(JSON.parse(response.body).url,'https://updates.test/updates/apk?version=1.16.4');
 }finally{
  await rm(directory,{recursive:true,force:true});
 }
});
