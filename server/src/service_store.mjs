import {createHash} from 'node:crypto';
import {ApiError} from './access.mjs';

// Internal service reads are limited by a separate PostgreSQL role.
export class ServiceStore {
 constructor(pool){this.pool=pool;}
 async using(work){
  const c=await this.pool.connect();
  try{await c.query('BEGIN');await c.query('SET LOCAL ROLE neural_service');const result=await work(c);await c.query('COMMIT');return result;}
  catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
 }
 async get(path){return this.using(async c=>(await c.query('SELECT document FROM neural.documents WHERE path=$1',[path])).rows[0]?.document?.fields??null);}
 async list(parent){return this.using(async c=>(await c.query('SELECT document FROM neural.documents WHERE parent_path=$1 ORDER BY path LIMIT 100',[parent])).rows.map(r=>r.document.fields));}
 async reserve(key,maximum,windowMs=600000){
  const digest=createHash('sha256').update(key).digest('hex');
  return this.using(async c=>{
   const result=await c.query(
    "INSERT INTO neural.service_limits(key,attempts) VALUES($1,1) ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN neural.service_limits.started_at<now()-($2::double precision*interval '1 millisecond') THEN 1 ELSE neural.service_limits.attempts+1 END,started_at=CASE WHEN neural.service_limits.started_at<now()-($2::double precision*interval '1 millisecond') THEN now() ELSE neural.service_limits.started_at END RETURNING attempts",[digest,windowMs]);
   await c.query("DELETE FROM neural.service_limits WHERE started_at<now()-interval '1 day'");
   return result.rows[0].attempts<=maximum;
  });
 }
 async schedule(key,payload){await this.using(c=>c.query("INSERT INTO neural.wake_jobs(key,payload,fire_at) VALUES($1,$2::jsonb,to_timestamp($3::double precision/1000)) ON CONFLICT(key) DO UPDATE SET payload=EXCLUDED.payload,fire_at=EXCLUDED.fire_at,retry_at=now(),attempts=0,lease_until=NULL",[key,JSON.stringify(payload),payload.fireAt]));}
 async cancel(key){await this.using(c=>c.query('DELETE FROM neural.wake_jobs WHERE key=$1',[key]));}
 async claim(){return this.using(async c=>(await c.query("WITH due AS (SELECT key FROM neural.wake_jobs WHERE fire_at<=now() AND retry_at<=now() AND (lease_until IS NULL OR lease_until<now()) ORDER BY fire_at FOR UPDATE SKIP LOCKED LIMIT 5) UPDATE neural.wake_jobs j SET lease_until=now()+interval '45 seconds',attempts=attempts+1 FROM due WHERE j.key=due.key RETURNING j.key,j.payload")).rows);}
 async complete(key,eventId,retry){await this.using(c=>retry?c.query("UPDATE neural.wake_jobs SET lease_until=NULL,retry_at=now()+interval '5 seconds' WHERE key=$1 AND payload->>'eventId'=$2",[key,eventId]):c.query("DELETE FROM neural.wake_jobs WHERE key=$1 AND payload->>'eventId'=$2",[key,eventId]));}
}
export const str=(fields,key)=>fields?.[key]?.stringValue;
export const bool=(fields,key)=>fields?.[key]?.booleanValue===true;
export const members=fields=>fields?.members?.arrayValue?.values?.map(v=>v.stringValue)??[];
export async function requirePair(store,sourceKey,uid,recipient){
 if(!uid||!/^(chat|couple)\/[A-Za-z0-9_-]{1,200}$/.test(sourceKey??'')||typeof recipient!=='string'||recipient===uid)throw new ApiError(403,'permission-denied','Bu kişiyle işlem yapılamaz.');
 const [kind,id]=sourceKey.split('/');
 const group=await store.get((kind==='chat'?'chats':'couples')+'/'+id),list=members(group);
 if(list.length!==2||!list.includes(uid)||!list.includes(recipient))throw new ApiError(403,'permission-denied','Bu sohbet için iznin yok.');
}
