import {privateUpdate} from './updates.mjs';
import {authenticateLegacyWake} from './legacy_wake.mjs';
import {Services} from './services.mjs';
import {WatchDelta,affectsWatch} from './watch_delta.mjs';
import {commit} from './commit.mjs';
import {storageStatus} from './storage.mjs';
import http from 'node:http';
import {createHash} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import pg from 'pg';
import {ApiError,docPath,mediaPaths} from './access.mjs';
import {authenticate} from './auth.mjs';
import {compileQuery} from './query.mjs';
initializeApp({projectId:process.env.FIREBASE_PROJECT_ID});
const pool=new pg.Pool({host:'/var/run/postgresql',database:'neural_haber',user:'neural_api',max:8,statement_timeout:10000,idle_in_transaction_session_timeout:10000});
const subscriptions=new Set(),buckets=new Map();
const services=new Services(pool);
let scheduling=false;
const scheduleTimer=setInterval(async()=>{
 if(scheduling)return;scheduling=true;
 try{await ready();if(primary)await services.scheduled();}
 catch{console.error(JSON.stringify({event:'schedule_check_failed'}));}
 finally{scheduling=false;}
},1000);
scheduleTimer.unref();
let readyUntil=0,primary=false;
async function ready(){
 if(Date.now()<readyUntil)return;
 const mode=await pool.query("SELECT value FROM neural.settings WHERE key='primary_writes'");
 primary=mode.rows[0]?.value===true;
 if(primary){readyUntil=Date.now()+1000;return;}
 const r=await pool.query('SELECT count(*) FILTER(WHERE collection_id<>\'__bridge_heartbeat\')::int AS total,count(*) FILTER(WHERE NOT ready)::int AS pending,COALESCE(bool_or(collection_id=\'__bridge_heartbeat\' AND updated_at>now()-interval \'45 seconds\'),false) AS alive FROM neural.sync_state');
 if(r.rows[0].total<30||r.rows[0].pending||!r.rows[0].alive)throw new ApiError(503,'unavailable','Sunucu hazırlanıyor. Biraz sonra yeniden dene.');
 readyUntil=Date.now()+1000;
}
async function withUser(uid,fn) {
 const db=await pool.connect();
 try {
  await db.query('BEGIN READ ONLY');
  await db.query("SELECT set_config('neural.uid',$1,true)",[uid]);
  const result=await fn(db);await db.query('COMMIT');return result;
 }catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}
}
async function read(body,auth) {
 await ready();
 if(body.kind==='documents'){
  const paths=mediaPaths(body.paths);
  const r=await withUser(auth.uid,db=>db.query('SELECT path,document,revision::text AS version FROM neural.documents WHERE path=ANY($1::text[])',[paths]));
  return {rows:r.rows};
 }
 if(body.kind==='document'){
  const path=docPath(body.path);
  const r=await withUser(auth.uid,db=>db.query('SELECT path,document,revision::text AS version FROM neural.documents WHERE path=$1',[path]));
  return {row:r.rows[0]??null};
 }
 const sql=compileQuery(body.query,auth.uid,{count:body.kind==='count'});
 const r=await withUser(auth.uid,db=>db.query(sql));
 return body.kind==='count'?{count:r.rows[0].count}:{rows:body.query.limitToLast?r.rows.reverse():r.rows};
}
function send(response,status,body) {
 response.writeHead(status,{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'});
 response.end(JSON.stringify(body));
}
function errorBody(e) {return {error:{code:e instanceof ApiError?e.code:'unavailable',message:e instanceof ApiError?e.message:'İşlem şu anda tamamlanamıyor. Biraz sonra yeniden dene.'}};}
async function bodyOf(request,maximum=65536,raw=false){
 let size=0;const chunks=[];
 for await(const chunk of request){size+=chunk.length;if(size>maximum)throw new ApiError(413,'resource-exhausted','İstek çok büyük.');chunks.push(chunk);}
 const text=Buffer.concat(chunks).toString('utf8');if(raw)return text;
 try{return JSON.parse(text);}catch{throw new ApiError(400,'invalid-argument','İstek okunamadı.');}
}
function rateLimit(uid,ip){
 const key=uid||ip;const now=Date.now();let item=buckets.get(key);
 if(!item||item.until<now){item={until:now+1000,n:0};buckets.set(key,item);}
 if(++item.n>120)throw new ApiError(429,'resource-exhausted','Çok hızlı işlem yapılıyor. Biraz bekle.');
 if(buckets.size>10000)for(const [k,v] of buckets)if(v.until<now)buckets.delete(k);
}
async function watch(body,auth,response){
 if(body.kind!=='document'&&body.kind!=='query')throw new ApiError(400,'invalid-argument','İzleme isteği geçersiz.');
 if(subscriptions.size>=300||[...subscriptions].filter(s=>s.uid===auth.uid).length>=40)throw new ApiError(429,'resource-exhausted','Çok fazla açık ekran var.');
 let last='',closed=false,running=false,dirty=false,flushTimer;
 const delta=body.delta===true?new WatchDelta():null;
 const initial=await read(body,auth);
 response.writeHead(200,{'content-type':'text/event-stream; charset=utf-8','cache-control':'no-store','x-accel-buffering':'no'});
 response.flushHeaders();
 const output=value=>{
  if(closed)return;
  if(delta){value=delta.next(value);if(value===null)return;}
  const data=JSON.stringify(value);
  if(data.length>64*1024*1024)throw new ApiError(413,'resource-exhausted','Bu liste çok büyük. Daha küçük bir bölüm aç.');
  const hash=createHash('sha256').update(data).digest('hex');
  if(hash!==last){if(response.writableLength>8*1024*1024)throw new ApiError(429,'resource-exhausted','Bağlantı yavaşladı.');response.write('data: '+data+'\n\n');last=hash;}
 };
 const tick=async()=>{
  if(closed)return;
  if(running){dirty=true;return;}running=true;
  try{output(await read(body,auth));}catch(e){if(!closed){response.write('event: failure\ndata: '+JSON.stringify(errorBody(e))+'\n\n');response.end();}}
  finally{running=false;if(dirty){dirty=false;queueMicrotask(tick);}}
 };
 const sub={uid:auth.uid,notify:(changed)=>{
  if(!affectsWatch(body,changed))return;
  dirty=true;
  if(!flushTimer)flushTimer=setTimeout(()=>{flushTimer=null;if(!closed){dirty=false;void tick();}},25);
 }};subscriptions.add(sub);
 const poll=setInterval(()=>{if(dirty){dirty=false;void tick();}else if(!closed)response.write(': ping\n\n');},1000);
 const expiryPoll=setInterval(()=>{void tick();},30000);
 const expires=setTimeout(()=>response.end(),Math.max(1,Math.min(auth.expires-Date.now(),30*60*1000)));
 const close=()=>{closed=true;clearTimeout(flushTimer);clearInterval(poll);clearInterval(expiryPoll);clearTimeout(expires);subscriptions.delete(sub);};
 response.once('close',close);response.once('error',close);
 try{output(initial);}catch{response.end();}
}
const server=http.createServer(async(request,response)=>{
 try{
  if(request.url==='/health'&&request.method==='GET'){await ready();send(response,200,{ok:true,status:'ready',mode:primary?'primary':'migration-bridge'});return;}
  if(request.url==='/storage/status'&&request.method==='GET'){
   const auth=await authenticate(request);
   if(!auth.uid)throw new ApiError(401,'unauthenticated','Depolamayı görmek için giriş yap.');
   rateLimit(auth.uid,request.socket.remoteAddress);
   send(response,200,await storageStatus(pool));return;
  }
  if(request.url==='/v1/capabilities'&&request.method==='GET'){
   await ready();
   send(response,200,{protocol:2,primaryWrites:primary});return;
  }
  const url=new URL(request.url,'https://138.2.185.151');
  if(request.method==='POST'&&url.pathname==='/internal/legacy-wake'){
   await ready();if(!primary)throw new ApiError(503,'unavailable','Geçiş henüz başlamadı.');
   const body=authenticateLegacyWake(request.headers,await bodyOf(request,4096,true));
   send(response,200,await services.nudge('/nudge',body,{uid:body.uid},{scheduled:true}));return;
  }
  if(request.method==='GET'&&['/updates/latest','/updates/apk'].includes(url.pathname)){
   const auth=await authenticate(request);rateLimit(auth.uid,request.socket.remoteAddress);
   await privateUpdate(services.store,auth,url,response);return;
  }
  if(request.method==='POST'&&['/call','/account/resolve','/nudge','/nudge/schedule','/nudge/cancel'].includes(url.pathname)){
   const auth=await authenticate(request);
   if(!auth.uid)throw new ApiError(401,'unauthenticated','Yeniden giriş yap.');
   await ready();
   if(!primary)throw new ApiError(503,'unavailable','Sunucu geçişi hazırlanıyor.');
   const ip=request.headers['x-real-ip']??request.socket.remoteAddress;
   rateLimit(auth.uid,ip);
   const body=await bodyOf(request,4096);
   const result=url.pathname==='/call'?await services.call(body,auth):url.pathname==='/account/resolve'?await services.account(body,auth,ip):await services.nudge(url.pathname,body,auth);
   send(response,200,result);return;
  }
  if(request.url==='/v1/commit'&&request.method==='POST'){
   const auth=await authenticate(request);
   if(!auth.uid)throw new ApiError(401,'unauthenticated','Oturumunu yeniden aç.');
   rateLimit(auth.uid,request.socket.remoteAddress);
   send(response,200,await commit(pool,await bodyOf(request,8*1024*1024),auth));return;
  }
  if(!['/v1/read','/v1/watch'].includes(request.url)||request.method!=='POST'){send(response,404,{error:{code:'not-found',message:'Bu adres bulunamadı.'}});return;}
  const auth=await authenticate(request);rateLimit(auth.uid,request.socket.remoteAddress);
  const body=await bodyOf(request);
  if(!['document','documents','query','count'].includes(body.kind))throw new ApiError(400,'invalid-argument','İşlem türü geçersiz.');
  if(request.url==='/v1/watch'){await watch(body,auth,response);return;}
  send(response,200,await read(body,auth));
 }catch(e){
  if(!response.headersSent)send(response,e instanceof ApiError?e.status:503,errorBody(e));else response.end();
  if(!(e instanceof ApiError))console.error(JSON.stringify({event:'request_failed',code:String(e.code??'unknown').slice(0,50)}));
 }
});
server.headersTimeout=15000;server.requestTimeout=120000;
server.listen(8080,'127.0.0.1',()=>console.log('{"event":"api_started"}'));
const listener=await pool.connect();
await listener.query('LISTEN neural_changes');
listener.on('notification',message=>{for(const s of subscriptions)s.notify(message.payload);});
listener.on('error',()=>{console.error('{"event":"database_listener_failed"}');process.exit(1);});
async function shutdown(){server.close();listener.release();await pool.end();process.exit(0);}
process.on('SIGTERM',shutdown);process.on('SIGINT',shutdown);
