import {transitionUpdate} from './transition_update.mjs';
import {checkStorage,storageStatus} from './storage.mjs';
import {notifyCall} from './calls.mjs';
import {resolveAccount} from './account_login.mjs';
import {privateUpdates} from './updates.mjs';
let cache;
const reply = (status, message) => Response.json({message}, {status});
const b64 = value => btoa(typeof value === 'string' ? value : String.fromCharCode(...new Uint8Array(value))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
async function accessToken(env, fetcher) {
  if (cache && cache.expires > Date.now()) return cache.token;
  const sa = JSON.parse(env.SERVICE_ACCOUNT_JSON), now = Math.floor(Date.now()/1000);
  const head = b64(JSON.stringify({alg:'RS256',typ:'JWT',kid:sa.private_key_id}));
  const body = b64(JSON.stringify({iss:sa.client_email,scope:'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/monitoring.read',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600}));
  const pem = sa.private_key.replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
  const key = await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(pem),c=>c.charCodeAt(0)),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(`${head}.${body}`));
  const r = await fetcher('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:`${head}.${body}.${b64(signature)}`})});
  if (!r.ok) throw Error('oauth');
  const data = await r.json(); cache={token:data.access_token,expires:Date.now()+50*60*1000}; return data.access_token;
}
export async function handle(request, env, deps={}) {
  const fetcher=deps.fetch??fetch, path=new URL(request.url).pathname;
  if(path==='/updates/transition/1.14.32.apk') return transitionUpdate(request,env,{fetch:fetcher,token:deps.token??(()=>accessToken(env,fetcher))});
  if(path.startsWith('/updates/')) return privateUpdates(request,env,{fetch:fetcher,token:deps.token??(()=>accessToken(env,fetcher))});
  if(request.method==='GET'&&path==='/health') return Response.json({ok:true,ready:!!(env.SERVICE_ACCOUNT_JSON&&env.FIREBASE_API_KEY&&env.FIREBASE_PROJECT_ID)});
  if(request.method==='GET'&&path==='/storage/status') return storageStatus(request,env,{fetch:fetcher,token:deps.token??(()=>accessToken(env,fetcher))});
  if(request.method==='POST'&&path==='/call') return notifyCall(request,env,{fetch:fetcher,token:deps.token??(()=>accessToken(env,fetcher))});
  if(request.method==='POST'&&path==='/account/resolve') return resolveAccount(request,env,{fetch:fetcher,token:deps.token??(()=>accessToken(env,fetcher))});
  if(request.method!=='POST'||!['/nudge','/nudge/schedule','/nudge/cancel'].includes(path)) return reply(404,'İşlem bulunamadı.');
  if(!env.SERVICE_ACCOUNT_JSON||!env.FIREBASE_API_KEY||!env.FIREBASE_PROJECT_ID) return reply(503,'Uyandırma hizmeti henüz hazır değil.');
  const auth=request.headers.get('Authorization')??'';
  if(!deps.scheduledUid && (!auth.startsWith('Bearer ')||auth.length>10000)) return reply(401,'Yeniden giriş yapmalısın.');
  try {
    const raw=await request.text(); if(raw.length>4096) return reply(400,'Geçersiz istek.');
    let body; try {body=JSON.parse(raw);} catch {return reply(400,'Geçersiz istek.');}
    const {sourceKey,recipientUid}=body;
    if(typeof sourceKey!=='string'||!/^(chat|couple)\/[A-Za-z0-9_-]{1,200}$/.test(sourceKey)||typeof recipientUid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(recipientUid)) return reply(400,'Sohbet bulunamadı.');
    let uid=deps.scheduledUid;
    if(!uid) {
      const login=await fetcher(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_API_KEY)}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({idToken:auth.slice(7)})});
      if(!login.ok) return reply(401,'Yeniden giriş yapmalısın.');
      uid=(await login.json()).users?.[0]?.localId;
    }
    if(!uid||uid===recipientUid) return reply(403,'Bu kişiyi uyandıramazsın.');
    const token=await(deps.token?deps.token():accessToken(env,fetcher));
    const root=`projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`, base=`https://firestore.googleapis.com/v1/${root}`;
    const api=(url,options={})=>fetcher(url,{...options,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'}});
    const get=async key=>{const r=await api(`${base}/${key}`);if(r.status===404)return null;if(!r.ok)throw Error('read');return r.json();};
    const [kind,id]=sourceKey.split('/');
    const source=await get(`${kind==='chat'?'chats':'couples'}/${id}`);
    const members=source?.fields?.members?.arrayValue?.values?.map(v=>v.stringValue)??[];
    if(members.length!==2||!members.includes(uid)||!members.includes(recipientUid)) return reply(403,'Bu kişiyi uyandıramazsın.');
    const scheduleObject=()=>env.WAKE_RATE.get(env.WAKE_RATE.idFromName(`wake-schedule:${uid}:${recipientUid}`));
    if(path==='/nudge/cancel') {
      await scheduleObject().fetch(new Request('https://internal/wake-schedule',{method:'DELETE'}));
      return reply(200,'Zamanlanmış uyandırma iptal edildi.');
    }
    const pr=await api(`${base}/chatAccounts/${recipientUid}:runQuery`,{method:'POST',body:JSON.stringify({structuredQuery:{from:[{collectionId:'wakePermissions'}],where:{fieldFilter:{field:{fieldPath:'sourceKey'},op:'EQUAL',value:{stringValue:sourceKey}}},limit:10}})});
    if(!pr.ok)throw Error('permissions');
    const permissions=(await pr.json()).filter(r=>r.document?.fields?.enabled?.booleanValue===true).map(r=>r.document.fields).filter(p=>/^[a-f0-9]{32}$/.test(p.deviceId?.stringValue??''));
    if(!permissions.length)return reply(403,'Bu kişi bu sohbetten uyandırılmayı açmamış.');
    if(path==='/nudge/schedule') {
      const fireAt=body.fireAt;
      if(!Number.isSafeInteger(fireAt)||fireAt<Date.now()+30000||fireAt>Date.now()+24*60*60*1000) return reply(400,'En az 30 saniye, en fazla 24 saat sonrası için saat seç.');
      const saved=await scheduleObject().fetch(new Request('https://internal/wake-schedule',{method:'PUT',body:JSON.stringify({uid,sourceKey,recipientUid,fireAt})}));
      if(!saved.ok) throw Error('schedule');
      return reply(200,'Uyandırma zamanlandı. Bu kişi için önceki planın yerini alır; internet ve telefon izinleri gerekir.');
    }
    let accepted=0;const eventId=crypto.randomUUID();
    for(const permission of permissions.slice(0,5)){
      const device=await get(`chatAccounts/${recipientUid}/wakeDevices/${permission.deviceId.stringValue}`), target=device?.fields?.token?.stringValue;
      if(!target)continue;
      const sent=await api(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`,{method:'POST',body:JSON.stringify({message:{token:target,data:{type:'wake',sourceKey,senderUid:uid,recipientUid,eventId,sentAt:`${Date.now()}`},android:{priority:'HIGH',ttl:'60s',collapse_key:'wake'}}})});
      if(sent.ok)accepted++;
    }
    return accepted?reply(200,'Uyandırma isteği iletildi. Telefonun bağlantısı ve izinlerine bağlı olarak çalacaktır.'):reply(503,'İstek iletilemedi. Bu kişinin uygulamayı açıp uyandırma ayarını kontrol etmesi gerekiyor.');
  }catch{return reply(503,'Uyandırma hizmetine şu anda ulaşılamıyor. Daha sonra yeniden dene.');}
}
export default {fetch:handle, async scheduled(controller,env) { await checkStorage(env,{token:()=>accessToken(env,fetch)}); }};

export class WakeRateLimiter {
  constructor(state,env) { this.state=state; this.env=env; }
  async alarm() {
    const job=await this.state.storage.get('wake-job');
    if(!job) return;
    if(Date.now()<job.fireAt) {await this.state.storage.setAlarm(job.fireAt);return;}
    await this.state.storage.delete('wake-job');
    // No stored ID tokens, passwords or location. Revalidate membership and consent now.
    if(Date.now()-job.fireAt>90000) return;
    await handle(new Request('https://internal/nudge',{method:'POST',body:JSON.stringify(job)}),this.env,{scheduledUid:job.uid});
  }
  async fetch(request) {
    const path=new URL(request.url).pathname;
    if(path==='/account/reserve'&&request.method==='POST') {
      const {limit}=await request.json();
      const accepted=await this.state.storage.transaction(async storage=>{
        let entry=await storage.get('account-attempts');
        if(!entry || Date.now()-entry.start>=10*60*1000) entry={start:Date.now(),count:0};
        if(entry.count>=Math.min(20,limit)) return false;
        entry.count++;await storage.put('account-attempts',entry);return true;
      });
      return new Response('',{status:accepted?200:429});
    }
    if(path==='/wake-schedule') {
      if(request.method==='DELETE') {await this.state.storage.delete('wake-job');await this.state.storage.deleteAlarm();return new Response('',{status:200});}
      if(request.method==='PUT') {
        const job=await request.json();
        await this.state.storage.put('wake-job',job);
        await this.state.storage.setAlarm(job.fireAt);
        return new Response('',{status:200});
      }
      return new Response('',{status:405});
    }
    if(path==='/storage/failure'&&request.method==='POST'){
      await this.state.storage.put('storage-last-attempt',Date.now()-24*60*60*1000+10*60*1000);
      return new Response('',{status:200});
    }
    if(path==='/storage/reserve'&&request.method==='POST'){
      const claimed=await this.state.storage.transaction(async storage=>{
        const last=await storage.get('storage-last-attempt')??0;
        if(Date.now()-last<24*60*60*1000)return false;
        await storage.put('storage-last-attempt',Date.now()); return true;
      });
      return new Response('',{status:claimed?200:429});
    }
    if(path==='/storage'){
      if(request.method==='GET'){
        const report=await this.state.storage.get('storage-latest');
        return report?Response.json(report):new Response('',{status:404});
      }
      if(request.method==='PUT'){
        const report=await request.json();
        const history=await this.state.storage.get('storage-history')??{};
        const month=report.checkedAt.slice(0,7);
        history[month]??=report;
        const keys=Object.keys(history).sort();
        for(const key of keys.slice(0,Math.max(0,keys.length-12)))delete history[key];
        await this.state.storage.put({'storage-latest':report,'storage-history':history});
        return new Response('',{status:200});
      }
    }
    if(request.method!=='POST')return new Response('',{status:405});
    // Kept for compatibility with the deployed Durable Object binding.
    // Nudges no longer call this object and no cooldown is enforced.
    return new Response('',{status:200});
  }
}
