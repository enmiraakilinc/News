// Sunucu kuralının otomatik sınamasıdır.
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

test('message pushes fan out concurrently while retaining the generic payload',async()=>{
 let active=0,maximum=0;
 const service=new Services({}, {push:async message=>{
  active++;maximum=Math.max(maximum,active);
  await new Promise(resolve=>setTimeout(resolve,5));
  active--;
  return message.data.type==='chat';
 }});
 service.store={
  get:async path=>path==='chats/direct'?chat:{scheduled:{booleanValue:false}},
  list:async()=>Array.from({length:5},(_,index)=>({token:encoded('fcm-device-token-'+index+'-123456')})),
 };
 await service.notifyChatMessages(['chats/direct/messages/message'],{uid:'sender'},'request-id');
 assert.equal(maximum,5);
});

test('multiple message notifications are sent once each in bounded batches',async()=>{
 const sent=[];let active=0,maximum=0;
 const service=new Services({}, {push:async message=>{
  active++;maximum=Math.max(maximum,active);
  sent.push(message);
  await new Promise(resolve=>setTimeout(resolve,5));
  active--;
  return true;
 }});
 service.store={
  get:async path=>path==='chats/direct'?chat:{scheduled:{booleanValue:false}},
  list:async()=>Array.from({length:5},(_,index)=>({token:encoded('fcm-device-token-'+index+'-123456')})),
 };
 await service.notifyChatMessages([
  'chats/direct/messages/first',
  'chats/direct/messages/second',
  'chats/direct/messages/third',
  'chats/direct/messages/third',
 ],{uid:'sender'},'request-id');
 assert.equal(sent.length,15);
 assert.equal(maximum,10);
 assert.deepEqual(
  sent.map(message=>message.data.messageId).sort(),
  [...Array(5).fill('first'),...Array(5).fill('second'),...Array(5).fill('third')].sort(),
 );
});
