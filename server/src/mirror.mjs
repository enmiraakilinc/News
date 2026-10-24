import {initializeApp,applicationDefault} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import pg from 'pg';
import {snapshotDocument} from './firestore_codec.mjs';
const project=process.env.FIREBASE_PROJECT_ID;
initializeApp({projectId:project,credential:applicationDefault()});
const pool=new pg.Pool({host:'/var/run/postgresql',database:'neural_haber',user:'neural_sync',max:2,statement_timeout:30000});
const firestore=getFirestore();
firestore.settings({useBigInt:true});
const extra=['accountCodeAliases','accountLoginCodes','chatInvites','chatMedia','chatProfiles','chats','config','couples','invites','updateAccess','voiceCalls','contacts','callDevices','starredMessages','wakeDevices','wakePermissions','names','chunks','preview','messages','courses','hiddenimages','letters','notes','questions','timeline','voicenotes','wishes','candidates','entries','downloadRequests','recipes','sharedLocations','mediaDownloadRequests'];
const rows=await pool.query('SELECT DISTINCT collection_id FROM neural.documents');
const groups=[...new Set([...extra,...rows.rows.map(r=>r.collection_id)])];
await pool.query('UPDATE neural.sync_state SET ready=false,error_code=NULL');
const streams=[];
for(const group of groups) {
 await pool.query('INSERT INTO neural.sync_state(collection_id,ready) VALUES($1,false) ON CONFLICT(collection_id) DO UPDATE SET ready=false,updated_at=now()', [group]);
 let initial=true,queue=Promise.resolve();
 const stop=firestore.collectionGroup(group).onSnapshot(snap=>{
  queue=queue.then(async()=>{
   const client=await pool.connect();
   try {
    await client.query('BEGIN');
    for(const change of snap.docChanges()) {
     const path=change.doc.ref.path;
     if(change.type==='removed') {await client.query('DELETE FROM neural.documents WHERE path=$1',[path]);continue;}
     const document=snapshotDocument(change.doc,project);
     await client.query(
      'INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document) VALUES($1,$2,$3,$4,$5::jsonb) ON CONFLICT(path) DO UPDATE SET document=EXCLUDED.document,changed_at=now(),revision=DEFAULT WHERE (EXCLUDED.document->>\'updateTime\')::timestamptz > (neural.documents.document->>\'updateTime\')::timestamptz',
      [path,path.split('/').slice(0,-1).join('/'),group,change.doc.id,JSON.stringify(document)]);
    }
    if(initial) {
     // Only the destination copy is reconciled; Firebase is never mutated.
     await client.query('DELETE FROM neural.documents WHERE collection_id=$1 AND NOT(path=ANY($2::text[]))',[group,snap.docs.map(d=>d.ref.path)]);
    }
    await client.query('INSERT INTO neural.sync_state(collection_id,ready,updated_at,error_code) VALUES($1,true,now(),NULL) ON CONFLICT(collection_id) DO UPDATE SET ready=true,updated_at=now(),error_code=NULL',[group]);
    await client.query('COMMIT');initial=false;
   }catch(e){
    await client.query('ROLLBACK');
    await client.query('UPDATE neural.sync_state SET ready=false,error_code=$2 WHERE collection_id=$1',[group,String(e.code??'sync-error').slice(0,80)]);
    console.error(JSON.stringify({event:'mirror_write_failed',code:e.code??'unknown'}));
    // Exit rather than dropping an event. Systemd reconnects and does a full
    // reconciliation, preserving correctness across transient database failures.
    process.exitCode=1;setTimeout(()=>process.exit(1),250);
   }finally{client.release();}
  });
 },async e=>{
  await pool.query('UPDATE neural.sync_state SET ready=false,error_code=$2 WHERE collection_id=$1',[group,String(e.code??'listen-error').slice(0,80)]);
  console.error(JSON.stringify({event:'mirror_listener_failed',code:e.code??'unknown'}));
  setTimeout(()=>process.exit(1),250);
 });
 streams.push(stop);
}
const pulse=async()=>pool.query("INSERT INTO neural.sync_state(collection_id,ready,updated_at,error_code) VALUES('__bridge_heartbeat',true,now(),NULL) ON CONFLICT(collection_id) DO UPDATE SET ready=true,updated_at=now(),error_code=NULL");
await pulse();
const heartbeat=setInterval(()=>{void pulse().catch(()=>{process.exitCode=1;process.exit(1);});},15000);
console.log(JSON.stringify({event:'mirror_started',groups:groups.length}));
async function shutdown(){clearInterval(heartbeat);for(const stop of streams)stop();await firestore.terminate();await pool.end();process.exit(0);}
process.on('SIGTERM',shutdown);process.on('SIGINT',shutdown);
