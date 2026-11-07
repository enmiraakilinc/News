import test from 'node:test';
import assert from 'node:assert/strict';
import {recordPresence} from '../src/presence.mjs';
import {ApiError} from '../src/access.mjs';

test('presence accepts explicit online and offline transitions',async()=>{
 const queries=[];
 const db={async query(sql,params){queries.push({sql,params});return{rows:[{value:true}],rowCount:1};},release(){}};
 const pool={async connect(){return db;}};
 const online=await recordPresence(pool,{uid:'alice'},{online:true});
 const offline=await recordPresence(pool,{uid:'alice'},{online:false});
 assert.deepEqual(online,{recorded:true});
 assert.deepEqual(offline,{recorded:true});
 const updates=queries.filter(({sql})=>sql.includes('UPDATE neural.documents'));
 assert.deepEqual(updates.map(({params})=>params[1]),[true,false]);
 assert.ok(updates.every(({sql})=>sql.includes("'{fields,online}'")));
 assert.ok(updates.every(({sql})=>sql.includes('$2::boolean=false')));
});

test('presence rejects missing or invalid online state',async()=>{
 const pool={async connect(){throw new Error('Should not connect for invalid input.');}};
 await assert.rejects(recordPresence(pool,{uid:'alice'},{}),ApiError);
 await assert.rejects(recordPresence(pool,{uid:'alice'},{online:'true'}),ApiError);
});
