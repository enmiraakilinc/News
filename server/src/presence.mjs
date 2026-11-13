import {ApiError} from './access.mjs';
// Ephemeral foreground activity does not enter the durable message outbox or
// commit-receipt history. The one existing opt-in record is updated in place.
export async function recordPresence(pool,auth,body){
 if(!auth.uid)throw new ApiError(401,'unauthenticated','Giriş yapmalısın.');
 if(typeof body?.online!=='boolean')throw new ApiError(400,'invalid-argument','Çevrimiçi durumu geçersiz.');
 const game=body.game??null;
 if(game!==null&&!['Sudoku','15 Taş','Block Blast'].includes(game))
  throw new ApiError(400,'invalid-argument','Oyun etkinliği geçersiz.');
 const db=await pool.connect();
 try{
  await db.query('BEGIN');await db.query('SET LOCAL ROLE neural_writer');
  const mode=await db.query("SELECT value FROM neural.settings WHERE key='primary_writes'");
  if(mode.rows[0]?.value!==true)throw new ApiError(503,'failed-precondition','Sunucuya geçiş henüz etkin değil.');
  await db.query("SELECT set_config('neural.uid',$1,true)",[auth.uid]);
  const result=await db.query(`UPDATE neural.documents SET
   document=jsonb_set(jsonb_set(jsonb_set(jsonb_set(document,'{fields}',
    (document->'fields'-'game')||CASE WHEN $3::text IS NULL THEN '{}'::jsonb
      ELSE jsonb_build_object('game',jsonb_build_object('stringValue',$3::text)) END),
    '{fields,online}',jsonb_build_object('booleanValue',$2::boolean)),
    '{fields,lastSeenAt}',jsonb_build_object('timestampValue',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))),
    '{updateTime}',to_jsonb(to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))),
   origin='postgres',revision=DEFAULT,changed_at=now()
   WHERE path=$1 AND document#>>'{fields,enabled,booleanValue}'='true'
   AND ($2::boolean=false OR document#>>'{fields,online,booleanValue}' IS DISTINCT FROM 'true'
    OR (document#>>'{fields,lastSeenAt,timestampValue}')::timestamptz<now()-interval '30 seconds'
    OR document#>>'{fields,game,stringValue}' IS DISTINCT FROM $3::text)`,
   ['chatAccounts/'+auth.uid+'/presence/status',body.online,game]);
  await db.query('COMMIT');return{recorded:result.rowCount>0};
 }catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}
}
