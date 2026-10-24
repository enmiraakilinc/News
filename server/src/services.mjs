import {randomUUID} from 'node:crypto';
import {ApiError} from './access.mjs';
import {ServiceStore,str,bool,requirePair} from './service_store.mjs';
import {deliverPush} from './push_transport.mjs';
export class Services {
 constructor(pool,{push=deliverPush}={}){this.store=new ServiceStore(pool);this.push=push;}
 async account(body,auth,ip){
  if(!auth.uid)throw new ApiError(401,'unauthenticated','Yeniden giriş yap.');
  if(!/^\d{12}$/.test(body.code??''))throw new ApiError(400,'invalid-argument','Hesap kodunu kontrol et.');
  for(const [key,limit] of [['ip:'+ip,20],['uid:'+auth.uid,10],['code:'+body.code,6]]){
   if(!await this.store.reserve(key,limit))throw new ApiError(429,'resource-exhausted','Çok fazla deneme yapıldı. 10 dakika sonra yeniden dene.');
  }
  const alias=await this.store.get('accountCodeAliases/'+body.code),email=str(alias,'email');
  if(!/^[a-f0-9]{32}@accounts\.neural\.invalid$/.test(email??''))throw new ApiError(404,'not-found','Hesap kodu veya şifre yanlış.');
  return {email};
 }
 async call(body,auth){
  if(!/^[A-Za-z0-9]{20}$/.test(body.id??'')||!['ring','end'].includes(body.action))throw new ApiError(400,'invalid-argument','Geçersiz arama.');
  const call=await this.store.get('voiceCalls/'+body.id),caller=str(call,'caller'),callee=str(call,'callee');
  if(!auth.uid||![caller,callee].includes(auth.uid))throw new ApiError(403,'permission-denied','Bu aramaya erişemezsin.');
  await requirePair(this.store,str(call,'sourceType')+'/'+str(call,'sourceId'),caller,callee);
  const ringing=body.action==='ring',age=Date.now()-Date.parse(call?.createdAt?.timestampValue);
  if(ringing&&(auth.uid!==caller||str(call,'state')!=='ringing'||!Number.isFinite(age)||age < -5000||age>45000)||!ringing&&str(call,'state')!=='ended')throw new ApiError(409,'failed-precondition','Arama sona ermiş.');
  if(!await this.store.reserve('call:'+body.id+':'+body.action+':'+auth.uid,3,60000))throw new ApiError(429,'resource-exhausted','Arama isteği zaten iletildi.');
  const recipient=ringing?callee:(auth.uid===caller?callee:caller);
  const devices=await this.store.list('chatAccounts/'+recipient+'/callDevices');
  let count=0;
  for(const device of devices.filter(d=>bool(d,'enabled')&&str(d,'token')).slice(0,5))
   if(await this.push({token:str(device,'token'),data:{type:ringing?'voice_call':'voice_call_end',callId:body.id,recipientUid:recipient},android:{priority:'HIGH',ttl:'45s',collapse_key:'call_'+body.id}}))count++;
  return {message:count?'Arama iletildi.':'Uygulama dışında arama alma ayarı açık değil; uygulama içinde arama bekleniyor.'};
 }
 async nudge(path,body,auth,{scheduled=false}={}){
  const {sourceKey,recipientUid}=body,uid=auth.uid;
  await requirePair(this.store,sourceKey,uid,recipientUid);
  const key=uid+':'+recipientUid;
  if(path==='/nudge/cancel'){await this.store.cancel(key);return {message:'Zamanlanmış uyandırma iptal edildi.'};}
  const permissions=(await this.store.list('chatAccounts/'+recipientUid+'/wakePermissions')).filter(p=>bool(p,'enabled')&&str(p,'sourceKey')===sourceKey&&/^[a-f0-9]{32}$/.test(str(p,'deviceId')??''));
  if(!permissions.length)throw new ApiError(403,'permission-denied','Bu kişi bu sohbetten uyandırılmayı açmamış.');
  if(path==='/nudge/schedule'){
   if(!Number.isSafeInteger(body.fireAt)||body.fireAt<Date.now()+30000||body.fireAt>Date.now()+86400000)throw new ApiError(400,'invalid-argument','30 saniye ile 24 saat arasında bir zaman seç.');
   await this.store.schedule(key,{uid,sourceKey,recipientUid,fireAt:body.fireAt,eventId:randomUUID()});
   return {message:'Uyandırma zamanlandı. Telefonun interneti ve gerekli izinleri açık olmalı.'};
  }
  const eventId=scheduled?body.eventId:randomUUID();let count=0;
  for(const permission of permissions.slice(0,5)){
   const device=await this.store.get('chatAccounts/'+recipientUid+'/wakeDevices/'+str(permission,'deviceId'));
   if(!str(device,'token'))continue;
   if(await this.push({token:str(device,'token'),data:{type:'wake',sourceKey,senderUid:uid,recipientUid,eventId,sentAt:String(Date.now())},android:{priority:'HIGH',ttl:'60s',collapse_key:'wake'}}))count++;
  }
  if(!count)throw new ApiError(503,'unavailable','İstek iletilemedi. Karşı telefonun uyandırma ayarını kontrol edin.');
  return {message:'Uyandırma isteği iletildi.'};
 }
 async scheduled(){
  for(const job of await this.store.claim()){
   let retry=false;
   try{if(Date.now()-job.payload.fireAt<=90000)await this.nudge('/nudge',job.payload,{uid:job.payload.uid},{scheduled:true});}
   catch(e){retry=!(e instanceof ApiError)||e.status>=500||e.status===429;}
   await this.store.complete(job.key,job.payload.eventId,retry);
  }
 }
}
