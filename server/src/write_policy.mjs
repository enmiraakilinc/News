import {isDeepStrictEqual as equal} from 'node:util';
import {ApiError,docPath} from './access.mjs';

export class Instant {
 constructor(nanos){this.nanos=BigInt(nanos);Object.freeze(this);}
 static parse(text){
  const m=/^(.+?)(?:\.(\d{1,9}))?Z$/.exec(text);
  if(!m)throw new ApiError(400,'invalid-argument','Tarih okunamadı.');
  const ms=Date.parse(m[1]+'Z');
  if(!Number.isFinite(ms))throw new ApiError(400,'invalid-argument','Tarih okunamadı.');
  return new Instant(BigInt(ms)*1000000n+BigInt((m[2]??'').padEnd(9,'0')));
 }
 add(ms){return new Instant(this.nanos+BigInt(ms)*1000000n);}
}
const only=(d,keys)=>d&&Object.keys(d).every(k=>keys.includes(k));
const changed=(a,b)=>[...new Set([...Object.keys(a??{}),...Object.keys(b??{})])].filter(k=>!equal(a?.[k],b?.[k]));
const changes=(a,b,keys)=>changed(a,b).every(k=>keys.includes(k));
const str=(v,min,max)=>typeof v==='string'&&[...v].length>=min&&[...v].length<=max;
const integer=(v,min,max)=>Number.isSafeInteger(v)&&v>=min&&v<=max;
const list=(v)=>Array.isArray(v);
const map=(v)=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&!(v instanceof Instant)&&!Buffer.isBuffer(v);
const has=(v,u)=>list(v)&&v.includes(u);
const at=(v,t)=>v instanceof Instant&&t instanceof Instant&&v.nanos===t.nanos;
const before=(v,t)=>v instanceof Instant&&t instanceof Instant&&v.nanos<t.nanos;
const expired=(d,now,ms=172800000)=>d?.createdAt instanceof Instant&&now.nanos>=d.createdAt.add(ms).nanos;
const validSource=v=>typeof v==='string'&&/^(chat|couple)\/[A-Za-z0-9_-]{1,200}$/.test(v);
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,200}$/.test(v);
const activeInvite=(d,now)=>d&&(d.createdAt instanceof Instant?before(now,d.createdAt.add(3600000)):before(now,d.expiresAt));
const image=d=>str(d?.avatarEmoji??d?.emoji??'',0,64)&&str(d?.avatarPhoto??d?.photo??'',0,32768)
 &&!((d?.avatarEmoji??d?.emoji??'')&&(d?.avatarPhoto??d?.photo??''));
const description=(v,type)=>only(v,['type','sdp'])&&v.type===type&&str(v.sdp,1,50000);

/** Port of firestore.rules. Default deny; read callbacks never escape to clients.
 * before is the pre-transaction document; readAfter sees the whole atomic batch.
 * Dates use exact nanoseconds so security comparisons do not lose precision.
 */
export async function authorizeWrite({path,before:a,after:b,uid,email,now,read,readAfter=read}){
 docPath(path);
 if(!uid||!(now instanceof Instant))throw new ApiError(401,'unauthenticated','Oturumunu yeniden aç.');
 const p=path.split('/'),create=!a&&!!b,remove=!b,update=!!a&&!!b;
 const member=async(kind,key)=>has((await read(kind+'/'+key))?.members,uid);
 const mediaMember=async d=>!!d&&(typeof d.chatId==='string'&&await member('chats',d.chatId)
   ||typeof d.coupleId==='string'&&await member('couples',d.coupleId));
 const voice=async d=>{
  if(!d||!['chat','couple'].includes(d.sourceType)||!id(d.sourceId)||d.sourceKey!==d.sourceType+'/'+d.sourceId
     ||![d.caller,d.callee].includes(uid)||d.caller===d.callee)return false;
  const source=await read((d.sourceType==='chat'?'chats':'couples')+'/'+d.sourceId);
  return source?.members?.length===2&&has(source.members,d.caller)&&has(source.members,d.callee);
 };
 const allow=()=>{
  return true;
 };
 const deny=()=>{throw new ApiError(403,'permission-denied','Bu işlem için erişim iznin yok.');};
 if(p[0]==='couples'){
  if(p.length>2)return await member('couples',p[1])?allow():deny();
  if(create)return has(b.members,uid)?allow():deny();
  if(remove)return has(a?.members,uid)?allow():deny();
  if(update){
   if(has(a.members,uid)&&(!changed(a,b).includes('joinProof')||b.joinProof===a.secretCheck))return allow();
   if(changes(a,b,['members','joinProof'])&&typeof a.secretCheck==='string'&&b.joinProof===a.secretCheck
      &&has(b.members,uid)&&list(a.members)&&a.members.every(u=>has(b.members,u))
      &&b.members.every(u=>a.members.includes(u)||u===uid)&&b.secretCheck===a.secretCheck)return allow();
  }
  return deny();
 }
 if(p[0]==='invites'&&p.length===2)return create||remove?allow():deny();
 if(p[0]==='chatAccounts'&&p[1]===uid&&['personalData','personalFiles','personalConfig'].includes(p[2])){
  if(p.length===4){
   if(remove)return p[2]!=='personalConfig'?allow():deny();
   if(p[2]==='personalConfig')return create&&p[3]==='sync'&&only(b,['secret','createdAt'])&&/^[a-f0-9]{64}$/.test(b.secret??'')&&at(b.createdAt,now)?allow():deny();
   if(p[2]==='personalData')return only(b,['kind','cipher','updatedAt'])&&['news','courseFolder','courseNote'].includes(b.kind)&&str(b.cipher,1,1000000)&&at(b.updatedAt,now)?allow():deny();
   return only(b,['size','count','ready','sha256','createdAt','expiresAt'])&&integer(b.size,1,104857600)&&integer(b.count,1,228)&&typeof b.ready==='boolean'&&/^[a-f0-9]{64}$/.test(b.sha256??'')&&b.createdAt instanceof Instant&&(!b.expiresAt||b.expiresAt instanceof Instant)?allow():deny();
  }
  if(p.length===6&&p[2]==='personalFiles'&&p[4]==='chunks'){
   if(remove)return allow();
   const parent=await readAfter(p.slice(0,4).join('/'));
   return parent&&/^\d{1,3}$/.test(p[5])&&Number(p[5])<parent.count&&only(b,['bytes','iv'])&&Buffer.isBuffer(b.bytes)&&b.bytes.length<=460816&&Buffer.isBuffer(b.iv)&&b.iv.length===16?allow():deny();
  }
  return deny();
 }
 if(p[0]==='chatAccounts'&&p.length===4&&p[1]===uid){
  const kind=p[2],key=p[3];
  if(kind==='contacts'){
   if(!b||!only(b,['alias','hidden','avatarEmoji','avatarPhoto'])||!image(b))return deny();
   if('alias'in b&&!str(b.alias,1,60)||'hidden'in b&&typeof b.hidden!=='boolean')return deny();
   return allow();
  }
  if(!['starredMessages','callDevices','wakeDevices','wakePermissions'].includes(kind))return deny();
  if(remove)return allow();
  if(!b)return deny();
  if(kind==='starredMessages'&&/^[a-f0-9]{64}$/.test(key)&&only(b,['sourceKey','messageId','starredAt'])
    &&validSource(b.sourceKey)&&id(b.messageId)&&at(b.starredAt,now))return allow();
  if(['callDevices','wakeDevices'].includes(kind)&&/^[a-f0-9]{32}$/.test(key)
    &&only(b,kind==='callDevices'?['token','enabled','updatedAt']:['token','updatedAt'])
    &&str(b.token,20,4096)&&(kind!=='callDevices'||typeof b.enabled==='boolean')&&at(b.updatedAt,now))return allow();
  if(kind==='wakePermissions'&&/^[a-f0-9]{64}$/.test(key)&&only(b,['sourceKey','enabled','volume','deviceId'])
    &&validSource(b.sourceKey)&&typeof b.enabled==='boolean'&&typeof b.volume==='number'&&b.volume>=0&&b.volume<=1
    &&/^[a-f0-9]{32}$/.test(b.deviceId??''))return allow();
  return deny();
 }
 if(p[0]==='chatProfiles'&&p.length===2){
  return b&&p[1]===uid&&only(b,['name','emoji','photo'])&&str(b.name,1,40)&&image(b)?allow():deny();
 }
 if(['chatContactLabels','coupleContactLabels'].includes(p[0])&&p.length===4&&p[2]==='names'&&p[3]===uid){
  if(!await member(p[0]==='chatContactLabels'?'chats':'couples',p[1]))return deny();
  return remove||b&&only(b,['label'])&&str(b.label,1,60)?allow():deny();
 }
 if(p[0]==='chatInvites'&&p.length===2){
  if(create){
   const profile=await read('chatProfiles/'+uid);
   if(/^[0-9]{8}$/.test(p[1])&&only(b,['owner','name','expiresAt','usedBy','createdAt'])&&b.owner===uid
     &&b.name===profile?.name&&b.usedBy===null
     &&(at(b.createdAt,now)&&b.expiresAt instanceof Instant
       ||!('createdAt'in b)&&before(now,b.expiresAt)&&!before(now.add(3900000),b.expiresAt)))return allow();
  }
  if(update&&a.owner!==uid&&a.usedBy===null&&activeInvite(a,now)&&changes(a,b,['usedBy'])&&b.usedBy===uid)return allow();
  if(remove&&a?.owner===uid)return allow();
  return deny();
 }
 if(p[0]==='chats'){
  if(p.length===2){
   if(update&&await member('chats',p[1])&&changes(a,b,['updatedAt'])&&at(b.updatedAt,now))return allow();
   if(!create||!only(b,['group','title','members','names','createdBy','updatedAt','inviteCode'])
     ||b.createdBy!==uid||!has(b.members,uid)||b.members.length<2||b.members.length>20
     ||new Set(b.members).size!==b.members.length||!b.members.every(u=>typeof u==='string')
     ||!map(b.names)||Object.keys(b.names).length!==b.members.length||!b.members.every(u=>Object.hasOwn(b.names,u))
     ||b.names[uid]!==(await read('chatProfiles/'+uid))?.name||!str(b.title,0,60)||!at(b.updatedAt,now))return deny();
   if(b.group===true&&b.title.length>0&&b.members.length>=3)return allow();
   if(b.group===false&&b.members.length===2&&typeof b.inviteCode==='string'){
    const invite=await readAfter('chatInvites/'+b.inviteCode);
    if(invite?.usedBy===uid&&activeInvite(invite,now)&&has(b.members,invite.owner)&&b.names[invite.owner]===invite.name)return allow();
   }
   return deny();
  }
  if(p.length!==4||p[2]!=='messages'||!await member('chats',p[1]))return deny();
  if(create&&only(b,['sender','text','sentAt','openAt','readBy','replyTo','scheduled'])&&b.sender===uid
    &&str(b.text,1,800000)&&at(b.sentAt,now)&&b.openAt instanceof Instant
    &&typeof(b.scheduled??true)==='boolean'&&((b.scheduled??true)||at(b.openAt,now))
    &&equal(b.readBy,[uid])&&(b.replyTo==null||typeof b.replyTo==='string'))return allow();
  if(remove&&a?.sender===uid)return allow();
  if(update&&a.openAt instanceof Instant&&!before(now,a.openAt)){
   if(changes(a,b,['readBy'])&&list(a.readBy)&&list(b.readBy)&&a.readBy.every(u=>b.readBy.includes(u))
      &&b.readBy.every(u=>a.readBy.includes(u)||u===uid))return allow();
   if(a.sender===uid&&changes(a,b,['text','editedAt'])&&str(b.text,1,800000)&&at(b.editedAt,now))return allow();
   if(changes(a,b,['reactions'])&&map(b.reactions)&&changes(a.reactions??{},b.reactions,[uid])&&str(b.reactions[uid]??'',0,64))return allow();
  }
  return deny();
 }
 if(p[0]==='voiceCalls'){
  if(p.length===4&&p[2]==='candidates'){
   const call=await read('voiceCalls/'+p[1]);
   if(!await voice(call))return deny();
   if(remove)return allow();
   if(create&&['ringing','accepted'].includes(call.state)
      &&(call.state==='accepted'||!expired(call,now,45000))
      &&only(b,['owner','candidate','sdpMid','sdpMLineIndex'])&&b.owner===uid&&str(b.candidate,0,2500)
      &&(b.sdpMid===null||typeof b.sdpMid==='string')
      &&(b.sdpMLineIndex===null||Number.isSafeInteger(b.sdpMLineIndex)))return allow();
   return deny();
  }
  if(p.length!==2)return deny();
  if(create&&await voice(b)&&only(b,['sourceKey','sourceType','sourceId','caller','callee','state','offer','createdAt','video'])
     &&b.caller===uid&&typeof(b.video??false)==='boolean'&&b.state==='ringing'&&at(b.createdAt,now)&&description(b.offer,'offer'))return allow();
  if(!await voice(a))return deny();
  if(remove&&a.caller===uid&&(a.state==='ended'||a.state==='ringing'&&expired(a,now,45000)))return allow();
  if(update){
   if(a.state==='ringing'&&a.callee===uid&&!expired(a,now,45000)&&changes(a,b,['state','answer','startedAt'])
      &&b.state==='accepted'&&at(b.startedAt,now)&&description(b.answer,'answer'))return allow();
   if(changes(a,b,['state','endedAt'])&&b.state==='ended'&&at(b.endedAt,now))return allow();
  }
  return deny();
 }
 if(p[0]==='chatMedia'){
  if(p.length===4&&['chunks','preview'].includes(p[2])){
   const media=await read('chatMedia/'+p[1]);
   if(!await mediaMember(media))return deny();
   if(remove&&(media.owner===uid||expired(media,now)))return allow();
   if(!create||media.owner!==uid||media.ready!==false||expired(media,now)||!only(b,['bytes','iv'])
      ||!Buffer.isBuffer(b.bytes)||b.bytes.length<1)return deny();
   if(media.coupleId===null?Object.hasOwn(b,'iv'):!Buffer.isBuffer(b.iv)||b.iv.length!==16)return deny();
   if(p[2]==='preview')return p[3]==='image'&&media.kind==='photo'&&b.bytes.length<=24592?allow():deny();
   return /^(0|[1-9][0-9]{0,2})$/.test(p[3])&&Number(p[3])<media.chunks&&b.bytes.length<=460816?allow():deny();
  }
  if(p.length!==2)return deny();
  if(create&&only(b,['owner','chatId','coupleId','name','kind','size','chunks','createdAt','ready'])&&b.owner===uid
     &&(typeof b.chatId==='string'&&b.coupleId===null||typeof b.coupleId==='string'&&b.chatId===null)
     &&await mediaMember(b)&&str(b.name,1,800)&&['file','photo','video','audio'].includes(b.kind)
     &&integer(b.size,1,b.kind==='video'?104857600:b.kind==='file'?83886080:20971520)
     &&integer(b.chunks,1,228)&&b.chunks===Math.ceil(b.size/460800)&&at(b.createdAt,now)&&b.ready===false)return allow();
  if(!await mediaMember(a))return deny();
  if(remove&&(a.owner===uid||expired(a,now))&&!await readAfter(path+'/preview/image'))return allow();
  if(update&&a.owner===uid
     &&(changes(a,b,['ready'])&&a.ready===false&&b.ready===true&&!expired(a,now)
       ||a.kind==='video'&&changes(a,b,['deleteRequestedAt'])&&at(b.deleteRequestedAt,now)))return allow();
  return deny();
 }
 if(p[0]==='mediaDownloadRequests'&&p.length===2){
  if(remove&&a&&[a.ownerUid,a.requesterUid].includes(uid))return allow();
  if(!b||typeof b.mediaId!=='string')return deny();
  const media=await read('chatMedia/'+b.mediaId);
  if(!media||media.ready!==true||expired(media,now)||!await mediaMember(media))return deny();
  if(create&&only(b,['mediaId','ownerUid','requesterUid','sourceKey','status','requestedAt','expiresAt'])
     &&p[1]===b.mediaId+'_'+uid&&b.requesterUid===uid&&b.ownerUid===media.owner&&media.owner!==uid
     &&['photo','video'].includes(media.kind)&&b.sourceKey===(typeof media.chatId==='string'?'chat/'+media.chatId:'couple/'+media.coupleId)
     &&at(b.expiresAt,media.createdAt.add(172800000))&&b.status==='pending'&&at(b.requestedAt,now))return allow();
  if(update&&a.ownerUid===uid&&media.owner===uid&&a.status==='pending'&&changes(a,b,['status','decidedAt'])
     &&['approved','declined'].includes(b.status)&&at(b.decidedAt,now))return allow();
  return deny();
 }
 if(p[0]==='sharedLocations'&&p.length===2){
  if(create&&only(b,['owner','chatId','coupleId','latitude','longitude','createdAt'])&&b.owner===uid
     &&(typeof b.chatId==='string'&&b.coupleId===null||typeof b.coupleId==='string'&&b.chatId===null)
     &&await mediaMember(b)&&typeof b.latitude==='number'&&b.latitude>=-90&&b.latitude<=90
     &&typeof b.longitude==='number'&&b.longitude>=-180&&b.longitude<=180&&at(b.createdAt,now))return allow();
  if(remove&&await mediaMember(a)&&(a.owner===uid||expired(a,now,3600000)))return allow();
  return deny();
 }
 if(p[0]==='accountCodeAliases'&&p.length===2&&create&&/^[0-9]{12}$/.test(p[1])
    &&only(b,['owner','email'])&&b.owner===uid&&b.email===email&&/^[a-f0-9]{32}@accounts[.]neural[.]invalid$/.test(b.email??'')
    &&!await read('accountLoginCodes/'+uid)&&(await readAfter('accountLoginCodes/'+uid))?.code===p[1])return allow();
 if(p[0]==='accountLoginCodes'&&p.length===2&&create&&p[1]===uid&&only(b,['code'])&&/^[0-9]{12}$/.test(b.code??'')
    &&(await readAfter('accountCodeAliases/'+b.code))?.owner===uid)return allow();
 return deny();
}
