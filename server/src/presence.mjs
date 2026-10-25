import {ApiError} from './access.mjs';
// Ephemeral foreground activity does not enter the durable message outbox or
// commit-receipt history. The one existing opt-in record is updated in place.
export async function recordPresence(pool,auth){
 if(!auth.uid)throw new ApiError(401,'unauthenticated','Giriş yapmalısın.');
 const db=await pool.connect();
 try{
  await db.query('BEGIN');await db.query('SET LOCAL ROLE neural_writer');
  const mode=await db.query("SELECT value FROM neural.settings WHERE key='primary_writes'");
  if(mode.rows[0]?.value!==true)throw new ApiError(503,'failed-precondition','Sunucuya geçiş henüz etkin değil.');
  await db.query("SELECT set_config('neural.uid',$1,true)",[auth.uid]);
  const result=await db.query(`UPDATE neural.documents SET
   document=jsonb_set(jsonb_set(document,'{fields,lastSeenAt}',jsonb_build_object('timestampValue',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))),
    '{updateTime}',to_jsonb(to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))),
   origin='postgres',revision=DEFAULT,changed_at=now()
   WHERE path=$1 AND document#>>'{fields,enabled,booleanValue}'='true'
   AND (document#>>'{fields,lastSeenAt,timestampValue}')::timestamptz<now()-interval '30 seconds'`,['chatAccounts/'+auth.uid+'/presence/status']);
  await db.query('COMMIT');return{recorded:result.rowCount>0};
 }catch(e){await db.query('ROLLBACK');throw e;}finally{db.release();}
}
