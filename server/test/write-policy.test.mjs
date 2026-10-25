import test from 'node:test';
import assert from 'node:assert/strict';
import {authorizeWrite,Instant} from '../src/write_policy.mjs';
const now=Instant.parse('2026-10-24T18:00:00.123456789Z');
const source={
 'couples/pair':{members:['alice','bob'],secretCheck:'correct'},
 'chats/direct':{members:['alice','bob']},
 'chatProfiles/alice':{name:'Alice'},
 'chatProfiles/bob':{name:'Bob'},
};
const run=(path,a,b,options={})=>authorizeWrite({path,before:a,after:b,uid:'alice',now,
 read:async p=>source[p],readAfter:options.read??(async p=>source[p]),...options});
const denied=p=>assert.rejects(p,e=>e.status===403);
const message={sender:'alice',text:'hello',sentAt:now,openAt:now,readBy:['alice'],replyTo:null,scheduled:false};
const media={owner:'alice',chatId:'direct',coupleId:null,name:'movie.mp4',
 kind:'video',size:104857600,chunks:228,createdAt:now,ready:false};
const call={sourceKey:'chat/direct',sourceType:'chat',sourceId:'direct',caller:'alice',callee:'bob',
 state:'ringing',createdAt:now,offer:{type:'offer',sdp:'test'}};

test('default deny protects config and another personal account',async()=>{
 await denied(run('config/app_version',null,{code:99999}));
 await denied(run('chatAccounts/bob/contacts/alice',null,{alias:'Alice'}));
 await denied(run('chatProfiles/bob',null,{name:'Alice'}));
 await run('chatAccounts/alice/contacts/bob',null,{alias:'Bob',avatarEmoji:'🌻'});
 await denied(run('chatAccounts/alice/contacts/bob',{alias:'Bob'},null));
});
test('chat membership never grants access to another couple',async()=>{
 await run('couples/pair/letters/a',null,{cipher:'encrypted'});
 await denied(run('couples/pair/letters/a',null,{cipher:'encrypted'},{uid:'outsider'}));
 await denied(run('couples/unknown/letters/a',null,{cipher:'encrypted'}));
});
test('couple joining needs the correct proof and preserves old members',async()=>{
 const a=source['couples/pair'];
 await run('couples/pair',a,{...a,members:[...a.members,'charlie'],joinProof:'correct'},{uid:'charlie'});
 await denied(run('couples/pair',a,{...a,members:[...a.members,'charlie'],joinProof:'wrong'},{uid:'charlie'}));
 await denied(run('couples/pair',a,{...a,members:['charlie'],joinProof:'correct'},{uid:'charlie'}));
});
test('message create uses authenticated identity and server timestamp',async()=>{
 await run('chats/direct/messages/a',null,message);
 await denied(run('chats/direct/messages/a',null,{...message,sender:'bob'}));
 await denied(run('chats/direct/messages/a',null,{...message,sentAt:now.add(-1)}));
 await denied(run('chats/direct/messages/a',null,{...message,openAt:now.add(1)}));
});
test('future messages cannot be edited or reacted to early',async()=>{
 const a={...message,scheduled:true,openAt:now.add(60000)};
 await denied(run('chats/direct/messages/a',a,{...a,text:'edited',editedAt:now}));
 await denied(run('chats/direct/messages/a',a,{...a,reactions:{alice:'👍'}}));
});
test('message updates cannot forge another sender or reaction',async()=>{
 await run('chats/direct/messages/a',message,{...message,text:'edited',editedAt:now});
 await denied(run('chats/direct/messages/a',message,{...message,sender:'bob',editedAt:now}));
 await denied(run('chats/direct/messages/a',message,{...message,text:'edited',editedAt:now},{uid:'bob'}));
 await run('chats/direct/messages/a',message,{...message,reactions:{alice:'🌷'}});
 await denied(run('chats/direct/messages/a',message,{...message,reactions:{bob:'🌷'}}));
 await run('chats/direct/messages/a',message,{...message,readBy:['alice','bob']},{uid:'bob'});
 await denied(run('chats/direct/messages/a',message,{...message,readBy:['alice','mallory']},{uid:'bob'}));
});
test('direct chat creation checks the consumed invite in the same batch',async()=>{
 const invite={owner:'bob',name:'Bob',usedBy:'alice',createdAt:now,expiresAt:now.add(3600000)};
 const b={group:false,title:'',members:['alice','bob'],names:{alice:'Alice',bob:'Bob'},
  createdBy:'alice',updatedAt:now,inviteCode:'12345678'};
 await run('chats/new',null,b,{readAfter:async p=>p==='chatInvites/12345678'?invite:source[p]});
 await denied(run('chats/new',null,b,{readAfter:async p=>p==='chatInvites/12345678'?{...invite,usedBy:'mallory'}:source[p]}));
 await denied(run('chats/new',null,b,{readAfter:async p=>p==='chatInvites/12345678'?{...invite,createdAt:now.add(-3600001)}:source[p]}));
});
test('video keeps 100 MiB and chunks remain bounded to the source owner',async()=>{
 await run('chatMedia/a',null,media);
 await denied(run('chatMedia/a',null,{...media,size:104857601}));
 await denied(run('chatMedia/a',null,{...media,chunks:227}));
 const read=async p=>p==='chatMedia/a'?media:source[p];
 await run('chatMedia/a/chunks/227',null,{bytes:Buffer.from([1,2])},{read});
 await denied(run('chatMedia/a/chunks/228',null,{bytes:Buffer.from([1,2])},{read}));
 await denied(run('chatMedia/a/chunks/0',null,{bytes:Buffer.from([1,2])},{read,uid:'bob'}));
 await denied(run('chatMedia/a/chunks/0',null,{bytes:Buffer.alloc(460817)},{read}));
});
test('encrypted media requires its IV; expired media cannot receive new chunks',async()=>{
 const encrypted={...media,chatId:null,coupleId:'pair'};
 await denied(run('chatMedia/a/chunks/0',null,{bytes:Buffer.from([1])},
  {read:async p=>p==='chatMedia/a'?encrypted:source[p]}));
 await run('chatMedia/a/chunks/0',null,{bytes:Buffer.from([1]),iv:Buffer.alloc(16)},
  {read:async p=>p==='chatMedia/a'?encrypted:source[p]});
 await denied(run('chatMedia/a/chunks/0',null,{bytes:Buffer.from([1])},
  {read:async p=>p==='chatMedia/a'?{...media,createdAt:now.add(-172800000)}:source[p]}));
});
test('accepted calls permit later ICE candidates without a 15 minute cutoff',async()=>{
 await run('voiceCalls/a',null,call);
 await denied(run('voiceCalls/a',null,call,{uid:'bob'}));
 const active={...call,state:'accepted',createdAt:now.add(-7200000)};
 const candidate={owner:'alice',candidate:'candidate',sdpMid:null,sdpMLineIndex:0};
 await run('voiceCalls/a/candidates/b',null,candidate,
  {read:async p=>p==='voiceCalls/a'?active:source[p]});
 await denied(run('voiceCalls/a/candidates/b',null,{...candidate,owner:'bob'},
  {read:async p=>p==='voiceCalls/a'?active:source[p]}));
 await denied(run('voiceCalls/a/candidates/b',null,candidate,
  {read:async p=>p==='voiceCalls/a'?{...active,state:'ringing'}:source[p]}));
});
test('download approval belongs to the sender and is bound to the media',async()=>{
 const active={...media,ready:true};
 const request={mediaId:'a',ownerUid:'alice',requesterUid:'bob',sourceKey:'chat/direct',
  status:'pending',requestedAt:now,expiresAt:now.add(172800000)};
 const read=async p=>p==='chatMedia/a'?active:source[p];
 await run('mediaDownloadRequests/a_bob',null,request,{uid:'bob',read});
 await run('mediaDownloadRequests/a_bob',request,{...request,status:'approved',decidedAt:now},{read});
 await denied(run('mediaDownloadRequests/a_bob',request,{...request,status:'approved',decidedAt:now},{uid:'bob',read}));
});
test('account alias cannot claim another UID or email',async()=>{
 const email='0123456789abcdef0123456789abcdef@accounts.neural.invalid';
 const readAfter=async p=>p==='accountLoginCodes/alice'?{code:'123456789012'}:source[p];
 await run('accountCodeAliases/123456789012',null,{owner:'alice',email},{email,readAfter});
 await denied(run('accountCodeAliases/123456789012',null,{owner:'bob',email},{email,readAfter}));
 await denied(run('accountCodeAliases/123456789012',null,{owner:'alice',email:'other@example.com'},{email,readAfter}));
});
test('timestamp comparisons keep nanoseconds and fail closed on missing bounds',async()=>{
 const a=Instant.parse('2026-10-24T18:00:00.123456788Z');
 await denied(run('chats/direct/messages/a',null,{...message,sentAt:a}));
});

test('only the sender can extend active media repeatedly without changing its contents',async()=>{
 const active={...media,ready:true},week={...active,expiresAt:now.add(7*86400000)};
 await run('chatMedia/a',active,week);
 await run('chatMedia/a',week,{...week,expiresAt:now.add(365*86400000)});
 await denied(run('chatMedia/a',active,week,{uid:'bob'}));
 await denied(run('chatMedia/a',active,{...week,owner:'bob'}));
 await denied(run('chatMedia/a',week,{...week,expiresAt:now.add(3*86400000)}));
 await denied(run('chatMedia/a',{...active,createdAt:now.add(-3*86400000)},week));
 await denied(run('chatMedia/a',media,{...media,expiresAt:now.add(7*86400000)}));
});

test('old automatic cleanup cannot delete active extended media, explicit sender delete still works',async()=>{
 const active={...media,ready:true,createdAt:now.add(-3*86400000),expiresAt:now.add(7*86400000)};
 const read=async p=>p==='chatMedia/a'?active:source[p];
 await denied(run('chatMedia/a',active,null,{read}));
 await denied(run('chatMedia/a/chunks/0',{bytes:Buffer.from([1])},null,{read}));
 await denied(run('chatMedia/a/chunks/0',{bytes:Buffer.from([1])},null,{uid:'bob',read}));
 const marked={...active,deleteRequestedAt:now};
 await run('chatMedia/a',active,marked);
 await run('chatMedia/a',marked,null,{read:async p=>p==='chatMedia/a'?marked:source[p]});
 await run('chatMedia/a/chunks/0',{bytes:Buffer.from([1])},null,{read:async p=>p==='chatMedia/a'?marked:source[p]});
});

test('extended download consent uses the new expiry and preserves approval',async()=>{
 const active={...media,ready:true,expiresAt:now.add(30*86400000)};
 const read=async p=>p==='chatMedia/a'?active:source[p];
 const request={mediaId:'a',ownerUid:'alice',requesterUid:'bob',sourceKey:'chat/direct',status:'pending',requestedAt:now,expiresAt:active.expiresAt};
 await run('mediaDownloadRequests/a_bob',null,request,{uid:'bob',read});
 const approved={...request,status:'approved',expiresAt:now.add(172800000)};
 await run('mediaDownloadRequests/a_bob',approved,{...approved,expiresAt:active.expiresAt},{read});
 await denied(run('mediaDownloadRequests/a_bob',approved,{...approved,expiresAt:active.expiresAt},{uid:'bob',read}));
});

test('last seen is owner-controlled, opt-in and timestamp-bound',async()=>{
 const p='chatAccounts/alice/presence/status',active={enabled:true,lastSeenAt:now};
 await run(p,null,active);
 await run(p,active,{enabled:false});
 await denied(run(p,active,{enabled:false,lastSeenAt:now}));
 await denied(run(p,null,active,{uid:'bob'}));
 await denied(run(p,active,{...active,lastSeenAt:now.add(-1000)}));
 await denied(run(p,{enabled:false},{enabled:false,lastSeenAt:now}));
});
test('only the owner can grant last-seen visibility to named peers',async()=>{
 const p='chatAccounts/alice/personalConfig/presence';
 await run(p,null,{peers:['bob']});
 await denied(run(p,null,{peers:['bob']},{uid:'bob'}));
 await denied(run(p,null,{peers:['bob','bob']}));
 await denied(run(p,null,{peers:['invalid/uid']}));
});
