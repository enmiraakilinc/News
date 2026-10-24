import test from 'node:test';
import assert from 'node:assert/strict';
import {mediaPaths} from '../src/access.mjs';
test('course media batches stay within one attachment',()=>{
 const path='couples/a/courses/b/entries/c/chunks/';
 assert.deepEqual(mediaPaths([path+'0',path+'227']),[path+'0',path+'227']);
 for(const values of [[path+'0',path.replace('/c/','/d/')+'1'],[path+'228'],['couples/a/letters/c/chunks/0']]) assert.throws(()=>mediaPaths(values));
});
import {storageStatus} from '../src/storage.mjs';

test('media batch is bounded and belongs to one attachment', () => {
  assert.deepEqual(mediaPaths(['chatMedia/a/chunks/0','chatMedia/a/chunks/227']),
    ['chatMedia/a/chunks/0','chatMedia/a/chunks/227']);
  for (const paths of [
    [],Array.from({length:17},(_,i)=>'chatMedia/a/chunks/'+i),
    ['chatMedia/a/chunks/0','chatMedia/b/chunks/1'],
    ['chatMedia/a/chunks/0','chatMedia/a/chunks/0'],
    ['chatMedia/a/chunks/228'],['chatMedia/a/chunks/../b'],
    ['chatInvites/12345678'],['chatAccounts/alice/contacts/bob'],
  ]) assert.throws(()=>mediaPaths(paths));
});

test('existing storage shape reports the VPS disk, not the Firestore quota', async () => {
  let calls=0;
  const pool={query:async()=>{calls++;return {rows:[{bytes:'701953727'}]};}};
  const report=await storageStatus(pool);
  assert.equal(report.provider,'oracle');
  assert.equal(report.databaseBytes,701953727);
  assert.ok(report.limitBytes>0);
  assert.ok(report.bytes>=0&&report.bytes<=report.limitBytes);
  assert.equal(report.bytes+report.freeBytes,report.limitBytes);
  assert.equal(report.warning,report.bytes>=report.limitBytes*0.8);
  assert.ok(Number.isFinite(Date.parse(report.checkedAt)));
  await storageStatus(pool);
  assert.equal(calls,1);
});
