import {ApiError,mediaPaths} from './access.mjs';

export function encodeMediaBatch(paths,rows){
 const entries=new Map(rows.map(r=>[r.path,r]));
 if(paths.some(p=>!entries.has(p)))throw new ApiError(403,'permission-denied','Dosya mevcut değil veya erişim süresi dolmuş.');
 const header=Buffer.alloc(6);header.write('NMC1');header.writeUInt16BE(paths.length,4);
 const parts=[header];
 for(const path of paths){
  const row=entries.get(path),bytes=Buffer.from(row.bytes??'','base64'),iv=Buffer.from(row.iv??'','base64');
  if(!bytes.length||bytes.length>460816||![0,16].includes(iv.length))throw new ApiError(503,'data-loss','Dosya parçası okunamadı.');
  const frame=Buffer.alloc(5);frame.writeUInt32BE(bytes.length);frame[4]=iv.length;
  parts.push(frame,iv,bytes);
 }
 return Buffer.concat(parts);
}

export async function mediaBinary(pool,auth,body){
 if(!auth.uid)throw new ApiError(401,'unauthenticated','Giriş yapmalısın.');
 const paths=mediaPaths(body?.paths),db=await pool.connect();
 try{
  await db.query('BEGIN READ ONLY');
  await db.query("SELECT set_config('neural.uid',$1,true)",[auth.uid]);
  const result=await db.query("SELECT path,document#>>'{fields,bytes,bytesValue}' AS bytes,document#>>'{fields,iv,bytesValue}' AS iv FROM neural.documents WHERE path=ANY($1::text[])",[paths]);
  const data=encodeMediaBatch(paths,result.rows);
  await db.query('COMMIT');return data;
 }catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}
}
