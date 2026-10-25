import {createHash} from 'node:crypto';
import {ApiError,docPath} from './access.mjs';
import {authorizeWrite,Instant} from './write_policy.mjs';
import {decodeFields,encodeFields,encodeTyped,applyWrite} from './write_codec.mjs';

export function validateCommitRequest(body){
 if(!body||! /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(body.requestId??'')
   ||!Array.isArray(body.operations)||!body.operations.length||body.operations.length>500
   ||!Array.isArray(body.conditions??[])||(body.conditions??[]).length>500)
  throw new ApiError(400,'invalid-argument','İşlem listesi geçersiz.');
 const paths=new Set();
 for(const op of body.operations){
  if(!op||typeof op!=='object')throw new ApiError(400,'invalid-argument','Invalid operation.');
  docPath(op.path);
  if(paths.has(op.path)||!['set','update','delete'].includes(op.type)
    ||Object.keys(op).some(k=>!['path','type','fields','merge','mergeFields'].includes(k)))
   throw new ApiError(400,'invalid-argument','İşlem alanları geçersiz.');
  paths.add(op.path);
 }
 for(const c of body.conditions??[]){
  if(!c||typeof c!=='object')throw new ApiError(400,'invalid-argument','Invalid condition.');
  docPath(c.path);
  if(c.version!==null&&(typeof c.version!=='string'||!/^[0-9]{1,20}$/.test(c.version)))
   throw new ApiError(400,'invalid-argument','Kayıt sürümü geçersiz.');
 }
 return body;
}
export async function commit(pool,body,auth){
 validateCommitRequest(body);
 if(!auth.uid||body.actorUid!==undefined&&body.actorUid!==auth.uid)throw new ApiError(401,'unauthenticated','Oturumunu yeniden aç.');
 const hash=createHash('sha256').update(JSON.stringify(body)).digest('hex');
 for(let attempt=0;attempt<4;attempt++){
  const db=await pool.connect();
  try{
   await db.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
   await db.query('SET LOCAL ROLE neural_writer');
   await db.query("SELECT set_config('neural.uid',$1,true)",[auth.uid]);
   await db.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))",[auth.uid+':'+body.requestId]);
   const prior=await db.query('SELECT request_hash,response FROM neural.commit_receipts WHERE uid=$1 AND request_id=$2',[auth.uid,body.requestId]);
   if(prior.rows.length){
    if(prior.rows[0].request_hash!==hash)throw new ApiError(409,'already-exists','İşlem kimliği başka bir kayıt için kullanılmış.');
    await db.query('COMMIT');return prior.rows[0].response;
   }
   const mode=await db.query("SELECT value FROM neural.settings WHERE key='primary_writes'");
   if(mode.rows[0]?.value!==true)throw new ApiError(503,'failed-precondition','Sunucuya yazma geçişi henüz etkin değil.');
   // Serialize metadata extensions/deletes with retention before checking time.
   for(const path of body.operations.map(op=>op.path).filter(p=>/^chatMedia\/[^/]+$/.test(p)).sort()){
    await db.query('SELECT path FROM neural.documents WHERE path=$1 FOR UPDATE',[path]);
   }
   const clock=await db.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') AS instant");
   const now=Instant.parse(clock.rows[0].instant),stamp=encodeTyped(now).timestampValue;
   const rows=new Map(),plain=new Map(),after=new Map();
   const load=async path=>{
    if(!rows.has(path)){
     const r=await db.query('SELECT document,revision::text AS version FROM neural.documents WHERE path=$1',[path]);
     rows.set(path,r.rows[0]??null);
    }
    return rows.get(path);
   };
   const read=async path=>{
    if(!plain.has(path)){
     const row=await load(path);plain.set(path,row?decodeFields(row.document.fields??{}):null);
    }
    return plain.get(path);
   };
   for(const condition of body.conditions??[]){
    const row=await load(condition.path);
    const permission=await db.query('SELECT neural.can_read($1,$2::jsonb,$3) AS allowed',
      [condition.path,row?JSON.stringify(row.document):null,auth.uid]);
    const knownMissing=!row&&/^(chats|voiceCalls)\/[^/]+$/.test(condition.path);
    if(!permission.rows[0].allowed&&!knownMissing)
     throw new ApiError(403,'permission-denied','İşlemdeki kayda erişim iznin yok.');
    if((row?.version??null)!==condition.version)throw new ApiError(409,'aborted','Kayıt değişti; işlem yeniden denenmeli.');
   }
   for(const op of body.operations)after.set(op.path,applyWrite(await read(op.path),op,now));
   const readAfter=async path=>after.has(path)?after.get(path):read(path);
   for(const op of body.operations){
    await authorizeWrite({path:op.path,before:await read(op.path),after:after.get(op.path),
      uid:auth.uid,email:auth.email,now,read,readAfter});
   }
   // Parents exist before inserting children; children disappear before parents.
   const ordered=[...body.operations].sort((a,b)=>{
    const ad=a.type==='delete',bd=b.type==='delete';
    if(ad!==bd)return ad?1:-1;
    return (ad?-1:1)*(a.path.split('/').length-b.path.split('/').length)||a.path.localeCompare(b.path);
   });
   const versions={},documents=[];let responseBytes=0;
   for(const op of ordered){
    const data=after.get(op.path);
    if(data===null){
     await db.query('DELETE FROM neural.documents WHERE path=$1',[op.path]);versions[op.path]=null;continue;
    }
    const parts=op.path.split('/');
    const previous=await load(op.path);
    const document={name:'projects/'+process.env.FIREBASE_PROJECT_ID+'/databases/(default)/documents/'+op.path,
      fields:encodeFields(data),createTime:previous?.document.createTime??stamp,updateTime:stamp};
    if(Buffer.byteLength(JSON.stringify(document))>1100000)throw new ApiError(413,'resource-exhausted','Kayıt çok büyük. İçeriği küçük parçalara ayır.');
    const result=await db.query(
     "INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document,origin) VALUES($1,$2,$3,$4,$5::jsonb,'postgres') ON CONFLICT(path) DO UPDATE SET document=EXCLUDED.document,origin='postgres',changed_at=now(),revision=DEFAULT RETURNING revision::text AS version",
     [op.path,parts.slice(0,-1).join('/'),parts.at(-2),parts.at(-1),JSON.stringify(document)]);
    versions[op.path]=result.rows[0].version;
    const bytes=Buffer.byteLength(JSON.stringify(document));
    if(parts.at(-2)!=='chunks'&&parts.at(-2)!=='preview'&&bytes<=131072&&responseBytes+bytes<=524288){
     documents.push({path:op.path,document,version:result.rows[0].version});responseBytes+=bytes;
    }
   }
   const response={requestId:body.requestId,commitTime:stamp,versions,documents};
   await db.query('INSERT INTO neural.commit_receipts(uid,request_id,request_hash,response) VALUES($1,$2,$3,$4::jsonb)',
    [auth.uid,body.requestId,hash,JSON.stringify(response)]);
   await db.query('COMMIT');return response;
  }catch(e){
   await db.query('ROLLBACK');
   if(['40001','40P01'].includes(e.code)&&attempt<3)continue;
   throw e;
  }finally{db.release();}
 }
 throw new ApiError(409,'aborted','İşlem yeniden denenmeli.');
}
