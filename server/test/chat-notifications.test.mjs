import test from 'node:test';
import assert from 'node:assert/strict';
import {Services} from '../src/services.mjs';

const encoded=value=>({stringValue:value});
const chat={members:{arrayValue:{values:[encoded('sender'),encoded('recipient')]} }};

test('new immediate chat messages push only a generic event to recipient devices',async()=>{
 const sent=[];
 const service=new Services({}, {push:async message=>{sent.push(message);return true;}});
 service.store={
  get:async path=>path==='chats/direct'?chat:
   path==='chats/direct/messages/message'?{scheduled:{booleanValue:false}}:null,
  list:async path=>path==='chatAccounts/recipient/chatDevices'?[{token:encoded('fcm-device-token-123456789')}]:[],
 };
 await service.notifyChatMessages(['chats/direct/messages/message'],{uid:'sender'},'request-id');
 assert.equal(sent.length,1);
 assert.deepEqual(sent[0].data,{
  type:'chat',recipientUid:'recipient',chatId:'direct',messageId:'message',eventId:'request-id_message',
 });
 assert.equal(sent[0].data.text,undefined);
 assert.equal(sent[0].android.priority,'HIGH');
});

test('scheduled and non-chat documents do not send push notifications',async()=>{
 const sent=[];
 const service=new Services({}, {push:async message=>{sent.push(message);return true;}});
 service.store={
  get:async()=>({scheduled:{booleanValue:true}}),
  list:async()=>[{token:encoded('fcm-device-token-123456789')}],
 };
 await service.notifyChatMessages(['chats/direct/messages/later','couples/pair/letters/letter'],{uid:'sender'},'request-id');
 assert.deepEqual(sent,[]);
});
