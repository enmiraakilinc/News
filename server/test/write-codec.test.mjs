import test from 'node:test';
import assert from 'node:assert/strict';
import {Instant} from '../src/write_policy.mjs';
import {decodeTyped,encodeTyped,encodeFields,decodeFields,applyWrite} from '../src/write_codec.mjs';
import {validateCommitRequest} from '../src/commit.mjs';

const now=Instant.parse('2026-10-24T18:00:00.123456789Z');
const transform=(operation,value)=>({transformValue:{operation,...(value===undefined?{}:{value:encodeTyped(value)})}});
test('write codec keeps timestamp nanoseconds, int64 and encrypted bytes',()=>{
 for(const value of [now,9223372036854775807n,Buffer.from([0,255,128]),{cipher:'sealed',nested:[true,null,1]}])
  assert.deepEqual(decodeTyped(encodeTyped(value)),value);
});
test('set merge retains unrelated keys and empty maps clear the selected map',()=>{
 const old={outer:{a:1,b:2},keep:3};
 const fields=encodeFields({outer:{a:4}});
 assert.deepEqual(applyWrite(old,{type:'set',fields,merge:true},now),{outer:{a:4,b:2},keep:3});
 assert.deepEqual(applyWrite(old,{type:'set',fields},now),{outer:{a:4}});
 assert.deepEqual(applyWrite(old,{type:'set',fields:encodeFields({outer:{}}),merge:true},now),{outer:{},keep:3});
 assert.deepEqual(applyWrite(old,{type:'set',fields:encodeFields({outer:{a:5,b:8}}),mergeFields:[['outer','a']]},now),{outer:{a:5,b:2},keep:3});
});
test('SDK field transforms share server time and preserve array uniqueness',()=>{
 const old={counter:2,users:['alice'],remove:'old',nested:{keep:true}};
 const output=applyWrite(old,{type:'update',fields:[
  {field:['counter'],value:transform('increment',3)},
  {field:['users'],value:transform('arrayUnion',['alice','bob'])},
  {field:['created'],value:transform('serverTimestamp')},
  {field:['edited'],value:transform('serverTimestamp')},
  {field:['remove'],value:transform('delete')},
 ]},now);
 assert.deepEqual(output,{counter:5,users:['alice','bob'],nested:{keep:true},created:now,edited:now});
 assert.deepEqual(applyWrite(output,{type:'update',fields:[
  {field:['users'],value:transform('arrayRemove',['alice'])},
 ]},now).users,['bob']);
});
test('int64 increments saturate instead of rounding to another number',()=>{
 const max=9223372036854775807n;
 assert.equal(applyWrite({n:max},{type:'update',fields:[{field:['n'],value:transform('increment',1)}]},now).n,max);
});
test('unsafe field paths, conflicting updates and malformed values are refused',()=>{
 for(const fields of [
  [{field:['__proto__','polluted'],value:encodeTyped(true)}],
  [{field:['a'],value:encodeTyped(1)},{field:['a','b'],value:encodeTyped(2)}],
 ]){
  assert.throws(()=>applyWrite({a:{}},{type:'update',fields},now),e=>e.status===400);
 }
 assert.throws(()=>decodeFields(JSON.parse('{"__proto__":{"mapValue":{"fields":{}}}}')),e=>e.status===400);
 assert.throws(()=>decodeTyped({integerValue:'9223372036854775808'}),e=>e.status===400);
 assert.throws(()=>decodeTyped({bytesValue:'not base64'}),e=>e.status===400);
 assert.throws(()=>applyWrite(null,{type:'update',fields:[]},now),e=>e.status===404);
 assert.equal({}.polluted,undefined);
});
test('invalid write envelopes and duplicate paths never reach SQL',()=>{
 const requestId='12345678-1234-4234-9234-123456789012';
 assert.throws(()=>validateCommitRequest({requestId,operations:[{type:'delete',path:'chats/a'},{type:'delete',path:'chats/a'}]}),e=>e.status===400);
 assert.throws(()=>validateCommitRequest({requestId,operations:[{type:'delete',path:'chats/a',sql:'bad'}]}),e=>e.status===400);
 assert.throws(()=>validateCommitRequest({requestId,operations:[{type:'delete',path:'chats/a'}],conditions:[{path:'chats/a',version:4}]}),e=>e.status===400);
});
