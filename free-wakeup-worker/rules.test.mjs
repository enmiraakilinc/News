import {before,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,getDocs,query,collection,where,updateDoc,deleteDoc,writeBatch,serverTimestamp,Timestamp,Bytes} from 'firebase/firestore';
let env,owner,peer,outsider;
const blob=Bytes.fromUint8Array(new Uint8Array([1,2,3]));
before(async()=>{
  env=await initializeTestEnvironment({projectId:'demo-neural-local',firestore:{host:'127.0.0.1',port:8181,
    rules:readFileSync(new URL('../firestore.rules',import.meta.url),'utf8')}});
  owner=env.authenticatedContext('owner').firestore();peer=env.authenticatedContext('peer').firestore();outsider=env.authenticatedContext('outsider').firestore();
  await env.withSecurityRulesDisabled(async context=>{
    await setDoc(doc(context.firestore(),'chats/one'),{members:['owner','peer']});
    await setDoc(doc(context.firestore(),'couples/pair'),{members:['owner','peer'],secretCheck:'test'});
  });
});
after(async()=>{await env?.cleanup();});
test('Video signaling is optional, boolean, immutable and retains real two-member access',async()=>{
  const data={sourceKey:'chat/one',sourceType:'chat',sourceId:'one',caller:'owner',callee:'peer',state:'ringing',offer:{type:'offer',sdp:'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'},createdAt:serverTimestamp(),video:true};
  await assertSucceeds(setDoc(doc(owner,'voiceCalls/video-call'),data));
  await assertSucceeds(getDoc(doc(peer,'voiceCalls/video-call')));
  await assertFails(getDoc(doc(outsider,'voiceCalls/video-call')));
  await assertFails(updateDoc(doc(owner,'voiceCalls/video-call'),{video:false}));
  await assertFails(setDoc(doc(owner,'voiceCalls/invalid-video'),{...data,video:'yes'}));
  await assertFails(setDoc(doc(outsider,'voiceCalls/outsider-video'),{...data,caller:'outsider'}));
});
test('Fifteen-minute calls retain ICE signaling beyond minute four and reject it after the bounded window',async()=>{
  await env.withSecurityRulesDisabled(async context=>{
    for(const [id,minutes] of [['long-call',5],['expired-long-call',17]]) {
      await setDoc(doc(context.firestore(),'voiceCalls/'+id),{sourceKey:'chat/one',sourceType:'chat',sourceId:'one',caller:'owner',callee:'peer',state:'accepted',createdAt:Timestamp.fromMillis(Date.now()-minutes*60000)});
    }
  });
  const candidate={owner:'owner',candidate:'candidate:valid',sdpMid:'0',sdpMLineIndex:0};
  await assertSucceeds(setDoc(doc(owner,'voiceCalls/long-call/candidates/a'),candidate));
  await assertFails(deleteDoc(doc(owner,'voiceCalls/long-call')));
  await assertFails(setDoc(doc(owner,'voiceCalls/expired-long-call/candidates/a'),candidate));
  await assertSucceeds(deleteDoc(doc(owner,'voiceCalls/expired-long-call')));
});
test('Short login aliases are immutable, owner-only, atomic and cannot change chat membership',async()=>{
  const email='a'.repeat(32)+'@accounts.neural.invalid';
  const db=env.authenticatedContext('login-owner',{email}).firestore();
  const alias=doc(db,'accountCodeAliases/123456789012'),index=doc(db,'accountLoginCodes/login-owner');
  await assertFails(setDoc(alias,{owner:'login-owner',email}));
  const batch=writeBatch(db);batch.set(alias,{owner:'login-owner',email});batch.set(index,{code:'123456789012'});await assertSucceeds(batch.commit());
  await assertSucceeds(getDoc(alias));
  await assertFails(getDoc(doc(peer,'accountCodeAliases/123456789012')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'accountCodeAliases/123456789012')));
  await assertFails(getDocs(collection(db,'accountCodeAliases')));
  await assertFails(updateDoc(alias,{email:'b'.repeat(32)+'@accounts.neural.invalid'}));
  await assertFails(setDoc(doc(peer,'accountLoginCodes/login-owner'),{code:'999999999999'}));
  const forged=writeBatch(db);forged.set(doc(db,'accountCodeAliases/999999999999'),{owner:'login-owner',email});forged.set(index,{code:'999999999999'});await assertFails(forged.commit());
  await assertFails(getDoc(doc(db,'chats/one')));
});
test('Background call device registration is opt-in and only writable/readable by its owner',async()=>{
  const path='chatAccounts/owner/callDevices/'+'c'.repeat(32);
  await assertSucceeds(setDoc(doc(owner,path),{enabled:true,token:'test-token-long-enough-for-device',updatedAt:serverTimestamp()}));
  await assertFails(getDoc(doc(peer,path)));
  await assertFails(updateDoc(doc(peer,path),{enabled:false,updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(owner,path),{enabled:'yes',updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(owner,path),{enabled:false,updatedAt:serverTimestamp()}));
});
test('Contact labels are shared only explicitly and only their owner can edit them',async()=>{
  const path='chatContactLabels/one/names/owner';
  await assertSucceeds(getDoc(doc(peer,path)));
  await assertSucceeds(setDoc(doc(owner,path),{label:'Defne'}));
  assert.equal((await assertSucceeds(getDoc(doc(peer,path)))).data().label,'Defne');
  await assertFails(setDoc(doc(peer,path),{label:'Tampered'}));
  await assertFails(getDoc(doc(outsider,path)));
  await assertSucceeds(deleteDoc(doc(owner,path)));
  await assertSucceeds(setDoc(doc(owner,'coupleContactLabels/pair/names/owner'),{label:'Melek'}));
  await assertFails(setDoc(doc(outsider,'coupleContactLabels/pair/names/outsider'),{label:'No'}));
});
const callData=()=>({sourceKey:'chat/one',sourceType:'chat',sourceId:'one',caller:'owner',callee:'peer',state:'ringing',offer:{type:'offer',sdp:'test-offer'},createdAt:serverTimestamp()});
test('Voice calls restrict signaling, acceptance and candidates to the two real members',async()=>{
  const path='voiceCalls/session';
  await assertFails(setDoc(doc(outsider,'voiceCalls/outsider'),{...callData(),caller:'outsider'}));
  await assertSucceeds(setDoc(doc(owner,path),callData()));
  await assertFails(getDoc(doc(outsider,path)));
  await assertSucceeds(getDocs(query(collection(peer,'voiceCalls'),where('callee','==','peer'))));
  await assertFails(getDocs(query(collection(outsider,'voiceCalls'),where('callee','==','peer'))));
  const answer={state:'accepted',answer:{type:'answer',sdp:'test-answer'},startedAt:serverTimestamp()};
  await assertFails(updateDoc(doc(owner,path),answer));
  await assertFails(updateDoc(doc(peer,path),{...answer,caller:'peer'}));
  await assertSucceeds(updateDoc(doc(peer,path),answer));
  const candidate={owner:'owner',candidate:'test-candidate',sdpMid:'0',sdpMLineIndex:0};
  await assertFails(setDoc(doc(peer,path+'/candidates/spoof'),candidate));
  await assertSucceeds(setDoc(doc(owner,path+'/candidates/ice'),candidate));
  await assertSucceeds(getDocs(query(collection(peer,path+'/candidates'),where('owner','==','owner'))));
  await assertSucceeds(updateDoc(doc(peer,path),{state:'ended',endedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(owner,path+'/candidates/late'),candidate));
  const batch=writeBatch(owner);batch.delete(doc(owner,path+'/candidates/ice'));batch.delete(doc(owner,path));await assertSucceeds(batch.commit());
});
test('Expired ringing calls cannot be accepted and client configuration cannot be enabled by clients',async()=>{
  await env.withSecurityRulesDisabled(async context=>setDoc(doc(context.firestore(),'voiceCalls/expired'),{...callData(),createdAt:Timestamp.fromMillis(Date.now()-60000)}));
  await assertFails(updateDoc(doc(peer,'voiceCalls/expired'),{state:'accepted',answer:{type:'answer',sdp:'late'},startedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(owner,'config/voice_calls'),{enabled:true}));
});
const metadata=(kind='photo',privatePair=false)=>({owner:'owner',chatId:privatePair?null:'one',coupleId:privatePair?'pair':null,
  name:'test',kind,size:10,chunks:1,createdAt:serverTimestamp(),ready:false});
test('Personal contact avatar is writable/readable only by its owner',async()=>{
  const path='chatAccounts/owner/contacts/one';
  await assertSucceeds(setDoc(doc(owner,path),{alias:'Selin',avatarEmoji:'🌙',avatarPhoto:''}));
  await assertSucceeds(getDoc(doc(owner,path)));
  await assertFails(getDoc(doc(peer,path)));
  await assertFails(setDoc(doc(peer,path),{avatarEmoji:'🔥'}));
  await assertFails(setDoc(doc(owner,path),{avatarEmoji:'🌙',avatarPhoto:'both'}));
});
test('Audio attachments obey existing readiness, membership and size constraints',async()=>{
  const path='chatMedia/audioTest';
  await assertSucceeds(setDoc(doc(owner,path),metadata('audio')));
  await assertSucceeds(setDoc(doc(owner,path+'/chunks/0'),{bytes:blob}));
  await assertFails(getDoc(doc(peer,path+'/chunks/0')));
  await assertSucceeds(updateDoc(doc(owner,path),{ready:true}));
  await assertSucceeds(getDoc(doc(peer,path+'/chunks/0')));
  await assertFails(getDoc(doc(outsider,path+'/chunks/0')));
  await assertFails(setDoc(doc(owner,'chatMedia/tooLargeAudio'),{...metadata('audio'),size:20*1024*1024+1,chunks:46}));
});
test('Photo preview expires with media; old parent-only deletion cannot orphan it',async()=>{
  const path='chatMedia/previewTest';
  await assertSucceeds(setDoc(doc(owner,path),metadata()));
  await assertSucceeds(setDoc(doc(owner,path+'/preview/image'),{bytes:blob}));
  await assertFails(getDoc(doc(peer,path+'/preview/image')));
  await assertSucceeds(updateDoc(doc(owner,path),{ready:true}));
  await assertSucceeds(getDoc(doc(peer,path+'/preview/image')));
  await assertFails(getDoc(doc(outsider,path+'/preview/image')));
  await assertFails(deleteDoc(doc(owner,path)));
  const batch=writeBatch(owner);batch.delete(doc(owner,path+'/preview/image'));batch.delete(doc(owner,path));
  await assertSucceeds(batch.commit());
});
test('Expired thumbnail is denied even to owner, and can be cleaned by a peer',async()=>{
  const path='chatMedia/expiredPreview';
  await env.withSecurityRulesDisabled(async context=>{
    await setDoc(doc(context.firestore(),path),{...metadata(),createdAt:Timestamp.fromMillis(Date.now()-49*60*60*1000),ready:true});
    await setDoc(doc(context.firestore(),path+'/preview/image'),{bytes:blob});
  });
  await assertFails(getDoc(doc(owner,path+'/preview/image')));
  const batch=writeBatch(peer);batch.delete(doc(peer,path+'/preview/image'));batch.delete(doc(peer,path));
  await assertSucceeds(batch.commit());
});
test('Private previews require encryption IV and preserve private membership',async()=>{
  const path='chatMedia/privatePreview';
  await assertSucceeds(setDoc(doc(owner,path),metadata('photo',true)));
  await assertFails(setDoc(doc(owner,path+'/preview/image'),{bytes:blob}));
  await assertSucceeds(setDoc(doc(owner,path+'/preview/image'),{bytes:blob,iv:Bytes.fromUint8Array(new Uint8Array(16))}));
  await assertSucceeds(updateDoc(doc(owner,path),{ready:true}));
  await assertSucceeds(getDoc(doc(peer,path+'/preview/image')));
  await assertFails(getDoc(doc(outsider,path+'/preview/image')));
});
test('Only recipient may enable its device/relationship; token and config stay protected',async()=>{
  const device='a'.repeat(32),permission='b'.repeat(64),path='chatAccounts/owner/wakePermissions/'+permission;
  const data={sourceKey:'chat/one',deviceId:device,enabled:true,volume:0.3};
  await assertSucceeds(setDoc(doc(owner,path),data));
  await assertFails(setDoc(doc(peer,path),{...data,enabled:true}));
  await assertFails(getDoc(doc(peer,path)));
  await assertFails(updateDoc(doc(owner,path),{volume:1.1}));
  const tokenPath='chatAccounts/owner/wakeDevices/'+device;
  await assertSucceeds(setDoc(doc(owner,tokenPath),{token:'fake-test-token-long-enough',updatedAt:serverTimestamp()}));
  await assertFails(getDoc(doc(peer,tokenPath)));
  await assertFails(setDoc(doc(owner,'config/wakeup'),{enabled:true,endpoint:'https://example.invalid'}));
});

test('Chat gallery requests require the real sender, membership and fresh photo/video; only sender can approve',async()=>{
  const id='AbCdEfGhIjKlMnOpQrSt', expired='AbCdEfGhIjKlMnOpQrSu';
  await env.withSecurityRulesDisabled(async ctx=>{
    const media={owner:'owner',chatId:'one',coupleId:null,name:'photo.jpg',kind:'photo',size:3,chunks:1,ready:true,createdAt:Timestamp.now()};
    await setDoc(doc(ctx.firestore(),'chatMedia/'+id),media);
    await setDoc(doc(ctx.firestore(),'chatMedia/'+expired),{...media,createdAt:Timestamp.fromMillis(Date.now()-3*86400000)});
  });
  const created=(await getDoc(doc(owner,'chatMedia/'+id))).data().createdAt;
  const data={expiresAt:Timestamp.fromMillis(created.toMillis()+2*86400000),mediaId:id,ownerUid:'owner',requesterUid:'peer',sourceKey:'chat/one',status:'pending',requestedAt:serverTimestamp()};
  const path='mediaDownloadRequests/'+id+'_peer';
  await assertSucceeds(getDoc(doc(peer,path)));
  await assertFails(setDoc(doc(outsider,'mediaDownloadRequests/'+id+'_outsider'),{...data,requesterUid:'outsider'}));
  await assertFails(setDoc(doc(peer,path),{...data,ownerUid:'outsider'}));
  await assertFails(setDoc(doc(peer,path),{...data,sourceKey:'chat/other'}));
  await assertFails(setDoc(doc(peer,path),{...data,status:'approved'}));
  await assertFails(setDoc(doc(peer,'mediaDownloadRequests/'+expired+'_peer'),{...data,mediaId:expired}));
  await assertSucceeds(setDoc(doc(peer,path),data));
  await assertSucceeds(getDocs(query(collection(owner,'mediaDownloadRequests'),where('ownerUid','==','owner'))));
  await assertFails(getDoc(doc(outsider,path)));
  await assertFails(updateDoc(doc(peer,path),{status:'approved',decidedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(owner,path),{status:'approved',requesterUid:'outsider',decidedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(owner,path),{status:'approved',decidedAt:serverTimestamp()}));
  await assertSucceeds(getDoc(doc(peer,path)));
  await assertFails(updateDoc(doc(owner,path),{status:'pending',decidedAt:serverTimestamp()}));
  await assertSucceeds(deleteDoc(doc(peer,path)));
});

test('Single 100 MB video is accepted; larger video and oversized other media stay rejected',async()=>{
  const size=100*1024*1024;
  const video={owner:'owner',chatId:'one',coupleId:null,name:'large.mp4',kind:'video',size,chunks:Math.ceil(size/460800),createdAt:serverTimestamp(),ready:false};
  await assertSucceeds(setDoc(doc(owner,'chatMedia/large-video'),video));
  await assertFails(setDoc(doc(owner,'chatMedia/too-large-video'),{...video,size:size+1}));
  await assertFails(setDoc(doc(owner,'chatMedia/wrong-chunks'),{...video,chunks:229}));
  await assertFails(setDoc(doc(owner,'chatMedia/too-large-photo'),{...video,kind:'photo'}));
  await assertFails(setDoc(doc(owner,'chatMedia/too-large-audio'),{...video,kind:'audio'}));
  await assertFails(setDoc(doc(owner,'chatMedia/too-large-file'),{...video,kind:'file'}));
  await assertFails(setDoc(doc(outsider,'chatMedia/outsider-large'),{...video,owner:'outsider'}));
  await assertFails(setDoc(doc(owner,'chatMedia/fake-large-owner'),{...video,owner:'peer'}));
});

test('Shared course folders and notes are restricted to pair members, not code-chat contacts',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{await setDoc(doc(ctx.firestore(),'chats/with-outsider'),{members:['owner','outsider']});});
  const folder='couples/pair/courses/program';
  await assertSucceeds(setDoc(doc(owner,folder),{owner:'owner',titleCipher:'encrypted-title',createdAt:serverTimestamp()}));
  await assertSucceeds(getDoc(doc(peer,folder)));
  await assertFails(getDoc(doc(outsider,folder)));
  await assertSucceeds(setDoc(doc(peer,folder+'/entries/code'),{owner:'peer',cipher:'encrypted-code',createdAt:serverTimestamp()}));
  await assertSucceeds(getDoc(doc(owner,folder+'/entries/code')));
  await assertFails(getDoc(doc(outsider,folder+'/entries/code')));
  await assertFails(setDoc(doc(outsider,folder+'/entries/forged'),{owner:'outsider',cipher:'x'}));
});
