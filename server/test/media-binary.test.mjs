import test from 'node:test';
import assert from 'node:assert/strict';
import {encodeMediaBatch} from '../src/media_binary.mjs';
test('binary media preserves request order, exact bytes and encryption IV',()=>{
 const paths=['chatMedia/a/chunks/0','chatMedia/a/chunks/1'];
 const iv=Buffer.alloc(16,7),first=Buffer.from([1,2,3]),last=Buffer.from([9,8]);
 const b=encodeMediaBatch(paths,[{path:paths[1],bytes:last.toString('base64'),iv:iv.toString('base64')},{path:paths[0],bytes:first.toString('base64')}]);
 assert.equal(b.subarray(0,4).toString(),'NMC1');assert.equal(b.readUInt16BE(4),2);
 assert.equal(b.readUInt32BE(6),3);assert.equal(b[10],0);assert.deepEqual(b.subarray(11,14),first);
 assert.equal(b.readUInt32BE(14),2);assert.equal(b[18],16);assert.deepEqual(b.subarray(19,35),iv);assert.deepEqual(b.subarray(35),last);
});
test('binary batch fails closed on missing, oversized or malformed pieces',()=>{
 const p=['chatMedia/a/chunks/0'];
 assert.throws(()=>encodeMediaBatch(p,[]),e=>e.status===403);
 assert.throws(()=>encodeMediaBatch(p,[{path:p[0],bytes:'AQ==',iv:'AQ=='}]),e=>e.status===503);
 assert.throws(()=>encodeMediaBatch(p,[{path:p[0],bytes:Buffer.alloc(460817).toString('base64')}]),e=>e.status===503);
});
