import test from 'node:test';
import assert from 'node:assert/strict';
import {docPath,queryAllowed,validateCommit} from '../src/access.mjs';
import {compileQuery} from '../src/query.mjs';
import {timestamp,encodeValue} from '../src/firestore_codec.mjs';
const value=s=>({stringValue:s});
test('reject traversal and control characters',()=>{
 for(const p of ['chats/a/../b','/chats/a','chats//a','chats/a/','chats/a\n','chatAccounts'])assert.throws(()=>docPath(p));
 assert.equal(docPath('couples/a/courses/b/entries/c'),'couples/a/courses/b/entries/c');
});
test('invites, login aliases and profiles cannot be enumerated',()=>{
 for(const path of ['invites','chatInvites','chatProfiles','accountCodeAliases','accountLoginCodes','config','couples'])assert.throws(()=>queryAllowed({path},'alice'));
});
test('address books are owner-only',()=>{
 assert.throws(()=>queryAllowed({path:'chatAccounts/bob/contacts'},'alice'));
 queryAllowed({path:'chatAccounts/alice/contacts'},'alice');
});
test('chat and call inboxes require the authenticated identity filter',()=>{
 assert.throws(()=>queryAllowed({path:'chats'},'alice'));
 assert.throws(()=>queryAllowed({path:'chats',filters:[{field:['members'],op:'array-contains',value:value('bob')}]},'alice'));
 queryAllowed({path:'chats',filters:[{field:['members'],op:'array-contains',value:value('alice')}]},'alice');
 assert.throws(()=>queryAllowed({path:'voiceCalls',filters:[{field:['callee'],op:'==',value:value('bob')}]},'alice'));
});
test('SQL fields and user values are always parameters',()=>{
 const evil="x'); DROP TABLE neural.documents;--";
 const q=compileQuery({path:'couples/a/letters',filters:[{field:[evil],op:'==',value:value(evil)}]},'alice');
 assert.ok(!q.text.includes(evil));assert.ok(q.values.some(v=>JSON.stringify(v).includes(evil)));
});
test('descending cursor uses document path to break equal timestamp ties',()=>{
 const q=compileQuery({path:'couples/a/letters',orders:[{field:['createdAt'],descending:true}],startAfter:[{timestampValue:'2026-10-24T14:00:00Z'},value('couples/a/letters/z')],limit:50},'alice');
 assert.match(q.text,/< /);assert.match(q.text,/to_jsonb\(path\) DESC/);assert.ok(q.values.includes(50));
});
test('count honours query limits',()=>{
 const q=compileQuery({path:'couples/a/letters',limit:50},'alice',{count:true});
 assert.match(q.text,/SELECT count\(\*\)::int/);assert.match(q.text,/LIMIT/);
});
test('int64 avoids JavaScript rounding',()=>{
 const q=compileQuery({path:'couples/a/letters',filters:[{field:['x'],op:'==',value:{integerValue:'9223372036854775807'}}]},'alice');
 assert.ok(q.values.includes('9223372036854775807'));
});
test('timestamp precision and bytes preserved',()=>{
 assert.equal(timestamp({seconds:0,nanoseconds:123456789}),'1970-01-01T00:00:00.123456789Z');
 assert.equal(timestamp({seconds:0,nanoseconds:123000000}),'1970-01-01T00:00:00.123Z');
 assert.deepEqual(encodeValue(Buffer.from([0,255,5])),{bytesValue:'AP8F'});
});
test('write envelopes cannot refer to another project',()=>{
 assert.throws(()=>validateCommit({writes:[{delete:'projects/other/databases/(default)/documents/chats/a'}]},'star-galeri'));
});

test('mirror serializes int64 without rounding',()=>{
 assert.deepEqual(encodeValue(9223372036854775807n),{integerValue:'9223372036854775807'});
});

test('timestamps compare as instants despite different fractional text precision',()=>{
 const q=compileQuery({path:'couples/a/letters',filters:[{field:['createdAt'],op:'==',value:{timestampValue:'2026-10-24T10:00:00.000000000Z'}}]},'alice');
 assert.match(q.text,/extract\(epoch FROM/);
 assert.ok(q.values.includes('2026-10-24T10:00:00.000000000Z'));
});
