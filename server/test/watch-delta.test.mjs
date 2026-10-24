import test from 'node:test';
import assert from 'node:assert/strict';
import {WatchDelta,affectsWatch} from '../src/watch_delta.mjs';
test('media chunk uploads do not refresh unrelated screens; access changes still do',()=>{
 const messages={kind:'query',query:{path:'chats/a/messages'}};
 assert.equal(affectsWatch(messages,'chatMedia/file/chunks/0'),false);
 assert.equal(affectsWatch(messages,'chats/a/messages/new'),true);
 assert.equal(affectsWatch(messages,'chats/a'),true);
 assert.equal(affectsWatch({kind:'document',path:'chatMedia/file/chunks/0'},'chatMedia/file'),true);
 assert.equal(affectsWatch({kind:'document',path:'chats/a/messages/one'},'chats/a/messages/two'),false);
});
const row=(path,version)=>({path,version,document:{fields:{cipher:{stringValue:'sealed'}}}});
test('live query sends full content once and only changed rows afterwards',()=>{
 const delta=new WatchDelta(),a=row('chats/a/messages/1','1'),b=row('chats/a/messages/2','2');
 assert.deepEqual(delta.next({rows:[a,b]}),{rows:[a,b]});
 assert.equal(delta.next({rows:[a,b]}),null);
 const edited=row(a.path,'3');
 assert.deepEqual(delta.next({rows:[edited,b]}),{patch:{upserts:[edited],remove:[],order:[a.path,b.path]}});
 assert.deepEqual(delta.next({rows:[b]}),{patch:{upserts:[],remove:[a.path],order:[b.path]}});
});
test('order-only updates retain existing media without resending its bytes',()=>{
 const delta=new WatchDelta(),a=row('a','1'),b=row('b','2');
 delta.next({rows:[a,b]});
 assert.deepEqual(delta.next({rows:[b,a]}),{patch:{upserts:[],remove:[],order:['b','a']}});
 assert.deepEqual(delta.next({rows:[]}),{patch:{upserts:[],remove:['b','a'],order:[]}});
});
