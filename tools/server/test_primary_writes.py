"""Run the pending primary-write layer in an isolated PostgreSQL database."""
from pathlib import Path
import base64,io,json,sys,tarfile,uuid
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute
nonce=uuid.uuid4().hex[:12]
roles={k:k+'_test_'+nonce for k in ['neural_api','neural_sync','neural_writer','neural_service']}
archive=io.BytesIO()
with tarfile.open(fileobj=archive,mode='w:gz') as tar:
    for name in ['access.mjs','write_policy.mjs','write_codec.mjs','commit.mjs','presence.mjs','service_store.mjs','services.mjs','push_transport.mjs']:
        content=(ROOT/'server/src'/name).read_text(encoding='utf-8')
        if name in ['commit.mjs','presence.mjs']:content=content.replace('SET LOCAL ROLE neural_writer','SET LOCAL ROLE '+roles['neural_writer'])
        if name=='service_store.mjs':content=content.replace('SET LOCAL ROLE neural_service','SET LOCAL ROLE '+roles['neural_service'])
        data=content.encode()
        info=tarfile.TarInfo(name);info.size=len(data)
        tar.addfile(info,io.BytesIO(data))
sql='\n'.join((ROOT/'server/sql'/name).read_text(encoding='utf-8') for name in
    ['001_documents.sql','002_read_access.sql','003_primary_writes.sql','004_retention.sql','005_services.sql','006_media_expiry.sql','007_presence.sql'])
for old,new in roles.items():sql=sql.replace(old,new)
test=r"""
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from '/opt/neural/server/node_modules/pg/lib/index.js';
import {commit} from './commit.mjs';
import {encodeFields,decodeFields} from './write_codec.mjs';
import {Services} from './services.mjs';
import {recordPresence} from './presence.mjs';
const database=process.env.TEST_DATABASE,api=process.env.TEST_API;
const admin=new pg.Pool({host:'/var/run/postgresql',database,user:'postgres'});
const clients=new pg.Pool({host:'/var/run/postgresql',database,user:'postgres',max:4});
const pool={connect:async()=>{
 const c=await clients.connect();
 await c.query('SET SESSION AUTHORIZATION '+api);
 return c;
}};
const auth={uid:'alice'};
const stamp={transformValue:{operation:'serverTimestamp'}};
const request=operations=>({requestId:randomUUID(),operations});
const base={
 'couples/pair':{members:['alice','bob'],secretCheck:'proof'},
 'chats/direct':{members:['alice','bob']},
 'couples/pair/notes/counter':{value:0},
};
let assertions=0;
try{
 for(const [path,data] of Object.entries(base)){
  const parts=path.split('/');
  await admin.query('INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document) VALUES($1,$2,$3,$4,$5::jsonb)',
   [path,parts.slice(0,-1).join('/'),parts.at(-2),parts.at(-1),JSON.stringify({fields:encodeFields(data)})]);
 }
 const c=await pool.connect();
 try{
  const permissions=await c.query("SELECT has_table_privilege(current_user,'neural.documents','INSERT') AS write");
  assert.equal(permissions.rows[0].write,false);assertions++;
 }finally{c.release();}
 const send=request([{type:'set',path:'chats/direct/messages/test',fields:{
  ...encodeFields({sender:'alice',text:'hello',readBy:['alice'],replyTo:null,scheduled:false}),
  sentAt:stamp,openAt:stamp,
 }}]);
 await assert.rejects(commit(pool,send,auth),e=>e.status===503);assertions++;
 await assert.rejects(recordPresence(pool,auth),e=>e.status===503);assertions++;
 await admin.query("UPDATE neural.settings SET value='true' WHERE key='primary_writes'");
 const first=await commit(pool,send,auth);
 const repeat=await commit(pool,send,auth);
 assert.deepEqual(first,repeat);assertions++;
 assert.equal((await admin.query('SELECT count(*)::int AS n FROM neural.commit_receipts')).rows[0].n,1);assertions++;
 await assert.rejects(commit(pool,{...send,operations:[{...send.operations[0],fields:encodeFields({text:'other'})}]},auth),e=>e.status===409);assertions++;
 await assert.rejects(commit(pool,request([{type:'update',path:'chats/direct/messages/test',
  fields:[{field:['text'],value:{stringValue:'forged'}},{field:['editedAt'],value:stamp}]}]),{uid:'bob'}),e=>e.status===403);assertions++;
 const increment=()=>request([{type:'update',path:'couples/pair/notes/counter',
  fields:[{field:['value'],value:{transformValue:{operation:'increment',value:{integerValue:'1'}}}}]}]);
 await Promise.all([commit(pool,increment(),auth),commit(pool,increment(),{uid:'bob'})]);
 let row=(await admin.query("SELECT document,revision::text AS version FROM neural.documents WHERE path='couples/pair/notes/counter'")).rows[0];
 assert.equal(decodeFields(row.document.fields).value,2);assertions++;
 const counter=increment();
 counter.conditions=[{path:'couples/pair/notes/counter',version:row.version}];
 await commit(pool,counter,auth);
 await assert.rejects(commit(pool,{...increment(),conditions:counter.conditions},auth),e=>e.code==='aborted');assertions++;
 await assert.rejects(commit(pool,request([{type:'set',path:'chatAccounts/bob/contacts/alice',fields:encodeFields({alias:'Alice'})}]),auth),e=>e.status===403);assertions++;
 await assert.rejects(commit(pool,request([
  {type:'set',path:'couples/pair/notes/atomic',fields:encodeFields({text:'allowed'})},
  {type:'set',path:'config/app_version',fields:encodeFields({code:999})},
 ]),auth),e=>e.status===403);assertions++;
 assert.equal((await admin.query("SELECT count(*)::int AS n FROM neural.documents WHERE path='couples/pair/notes/atomic'")).rows[0].n,0);assertions++;
 row=(await admin.query("SELECT origin FROM neural.documents WHERE path='chats/direct/messages/test'")).rows[0];
 assert.equal(row.origin,'postgres');assertions++;
 assert.ok(first.documents.some(d=>d.path==='chats/direct/messages/test'));assertions++;
 // Service fixtures are isolated from real user data and never send an FCM push.
 const insert=async(path,fields)=>{
  const p=path.split('/');await admin.query('INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document) VALUES($1,$2,$3,$4,$5::jsonb)',[path,p.slice(0,-1).join('/'),p.at(-2),p.at(-1),JSON.stringify({fields})]);
 };
 const stampAt=days=>({timestampValue:new Date(Date.now()-days*86400000).toISOString()});
 const media={...encodeFields({owner:'alice',chatId:'direct',ready:true}),createdAt:stampAt(3)};
 await insert('chatMedia/old',media);await insert('chatMedia/old/chunks/0',encodeFields({bytes:Buffer.from([1])}));
 await insert('chatMedia/fresh',{...media,createdAt:stampAt(0)});await insert('chatMedia/fresh/chunks/0',encodeFields({bytes:Buffer.from([1])}));
 await insert('chatMedia/extended',{...media,createdAt:stampAt(3),expiresAt:stampAt(-7)});
 await insert('chatMedia/extended/chunks/0',encodeFields({bytes:Buffer.from([1])}));
 const note='couples/pair/courses/course/entries/note';
 await insert(note,{...encodeFields({cipher:'keep note'}),createdAt:stampAt(8)});
 await insert(note+'/chunks/0',encodeFields({bytes:Buffer.from([1])}));
 await insert('couples/pair/timeline/permanent',{...encodeFields({img:'keep memory'}),createdAt:stampAt(8)});
 const reader=await pool.connect();
 try{
  await reader.query('BEGIN');await reader.query("SELECT set_config('neural.uid','alice',true)");
  assert.equal((await reader.query('SELECT path FROM neural.documents WHERE path=$1',[note+'/chunks/0'])).rowCount,0);assertions++;
  await reader.query('ROLLBACK');
 }finally{reader.release();}
 assert.equal((await admin.query('SELECT neural.prune_expired(500) AS n')).rows[0].n,3);assertions++;
 for(const path of ['chatMedia/fresh/chunks/0','chatMedia/extended','chatMedia/extended/chunks/0',note,'couples/pair/timeline/permanent','chats/direct/messages/test']){
  assert.equal((await admin.query('SELECT path FROM neural.documents WHERE path=$1',[path])).rowCount,1);assertions++;
 }
 let pushes=0;const services=new Services(pool,{push:async()=>{pushes++;return true;}});
 assert.equal(await services.store.get('couples/pair/notes/counter'),null);assertions++;
 const id='ABCDEFGHIJKLMNOPQRST',device='a'.repeat(32);
 await insert('voiceCalls/'+id,{...encodeFields({caller:'alice',callee:'bob',sourceType:'chat',sourceId:'direct',state:'ringing'}),createdAt:stampAt(0)});
 await insert('chatAccounts/bob/callDevices/'+device,encodeFields({enabled:true,token:'test-device-token-123456789'}));
 await assert.rejects(services.call({id,action:'ring'},{uid:'outsider'}),e=>e.status===403);assertions++;
 await services.call({id,action:'ring'},auth);assert.equal(pushes,1);assertions++;
 const alias='123456789012',email='a'.repeat(32)+'@accounts.neural.invalid';
 await insert('accountCodeAliases/'+alias,encodeFields({owner:'alice',email}));
 assert.deepEqual(await services.account({code:alias},auth,'test-ip'),{email});assertions++;
 for(let i=0;i<5;i++)await services.account({code:alias},auth,'test-ip');
 await assert.rejects(services.account({code:alias},auth,'test-ip'),e=>e.status===429);assertions++;
 await insert('chatAccounts/bob/wakePermissions/consent',encodeFields({enabled:true,sourceKey:'chat/direct',deviceId:device}));
 await insert('chatAccounts/bob/wakeDevices/'+device,encodeFields({token:'test-device-token-123456789'}));
 await assert.rejects(services.nudge('/nudge',{sourceKey:'chat/direct',recipientUid:'bob'},{uid:'outsider'}),e=>e.status===403);assertions++;
 await services.nudge('/nudge/schedule',{sourceKey:'chat/direct',recipientUid:'bob',fireAt:Date.now()+60000},auth);
 assert.equal((await admin.query('SELECT count(*)::int AS n FROM neural.wake_jobs')).rows[0].n,1);assertions++;
 await services.nudge('/nudge/cancel',{sourceKey:'chat/direct',recipientUid:'bob'},auth);
 assert.equal((await admin.query('SELECT count(*)::int AS n FROM neural.wake_jobs')).rows[0].n,0);assertions++;
 await services.store.schedule('alice:bob',{uid:'alice',sourceKey:'chat/direct',recipientUid:'bob',fireAt:Date.now()-100,eventId:randomUUID()});
 await services.scheduled();assert.equal(pushes,2);assertions++;
 assert.equal((await admin.query('SELECT count(*)::int AS n FROM neural.wake_jobs')).rows[0].n,0);assertions++;
 const personal='chatAccounts/alice/personalData/news_private';
 await commit(pool,request([{type:'set',path:personal,fields:{...encodeFields({kind:'news',cipher:'encrypted personal note'}),updatedAt:stamp}}]),auth);
 await assert.rejects(commit(pool,request([{type:'set',path:personal,fields:{...encodeFields({kind:'news',cipher:'forged'}),updatedAt:stamp}}]),{uid:'bob'}),e=>e.status===403);assertions++;
 const privateFile='chatAccounts/alice/personalFiles/expired';
 await insert(privateFile,{...encodeFields({size:1,count:1,ready:true,sha256:'a'.repeat(64)}),expiresAt:stampAt(1)});
 await insert(privateFile+'/chunks/0',encodeFields({bytes:Buffer.from([1]),iv:Buffer.alloc(16)}));
 const checkRead=async(uid,path)=>{
  const c=await pool.connect();try{await c.query('BEGIN');await c.query("SELECT set_config('neural.uid',$1,true)",[uid]);
   const result=await c.query('SELECT path FROM neural.documents WHERE path=$1',[path]);await c.query('ROLLBACK');return result.rowCount;
  }finally{c.release();}
 };
 assert.equal(await checkRead('alice','chatMedia/extended/chunks/0'),1);assertions++;
 assert.equal(await checkRead('outsider','chatMedia/extended/chunks/0'),0);assertions++;
 const presence='chatAccounts/alice/presence/status';
 const presenceConsent='chatAccounts/alice/personalConfig/presence';
 await commit(pool,request([{type:'set',path:presenceConsent,fields:encodeFields({peers:['bob']})}]),auth);
 await commit(pool,request([{type:'set',path:presence,fields:{...encodeFields({enabled:true}),lastSeenAt:stamp}}]),auth);
 assert.equal(await checkRead('alice',presence),1);assertions++;
 assert.equal(await checkRead('bob',presence),1);assertions++;
 assert.equal(await checkRead('outsider',presence),0);assertions++;
 await commit(pool,request([{type:'set',path:'couples/forged',fields:encodeFields({members:['alice','outsider']})}]),{uid:'outsider'});
 assert.equal(await checkRead('outsider',presence),0);assertions++;
 assert.equal(await checkRead('bob',presenceConsent),0);assertions++;
 const receiptsBefore=(await admin.query('SELECT count(*)::int AS n FROM neural.commit_receipts')).rows[0].n;
 await admin.query("UPDATE neural.documents SET document=jsonb_set(document,'{fields,lastSeenAt}',jsonb_build_object('timestampValue',to_char(now()-interval '1 minute','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'))) WHERE path=$1",[presence]);
 assert.equal((await recordPresence(pool,auth)).recorded,true);assertions++;
 assert.equal((await recordPresence(pool,auth)).recorded,false);assertions++;
 assert.equal((await admin.query('SELECT count(*)::int AS n FROM neural.commit_receipts')).rows[0].n,receiptsBefore);assertions++;
 await commit(pool,request([{type:'set',path:presence,fields:encodeFields({enabled:false})}]),auth);
 assert.equal((await recordPresence(pool,auth)).recorded,false);assertions++;
 await assert.rejects(commit(pool,request([{type:'update',path:presence,fields:[{field:['lastSeenAt'],value:stamp}]}]),auth),e=>e.status===403);assertions++;
 assert.equal(await checkRead('alice',personal),1);assertions++;
 assert.equal(await checkRead('bob',personal),0);assertions++;
 assert.equal(await checkRead('bob',privateFile),0);assertions++;
 assert.equal(await checkRead('alice',privateFile+'/chunks/0'),0);assertions++;
 assert.equal(await services.store.get(personal),null);assertions++;
 assert.equal((await admin.query('SELECT neural.prune_expired(500) AS n')).rows[0].n,2);assertions++;
 assert.equal(await checkRead('alice',personal),1);assertions++;
 console.log(JSON.stringify({isolatedDatabase:true,primaryWriteChecks:assertions,
  idempotency:true,concurrentIncrement:true,atomicRollback:true,readRoleCannotWrite:true,
  productionUserDataModified:false}));
}finally{await clients.end();await admin.end();}
"""
script=r"""
import base64,io,os,pathlib,shutil,subprocess,tarfile
def run(*args,**kwargs):
    return subprocess.run(list(args),check=True,text=True,**kwargs)
def check(options):
    name='neural_primary_test_'+options['nonce']
    folder=pathlib.Path('/var/tmp')/name
    assert folder.resolve().parent==pathlib.Path('/var/tmp') and name.startswith('neural_primary_test_')
    created=False
    folder.mkdir(mode=0o755)
    try:
        with tarfile.open(fileobj=io.BytesIO(base64.b64decode(options['archive'])),mode='r:gz') as t:
            t.extractall(folder,filter='data')
        (folder/'verify.mjs').write_text(options['test'])
        run('sudo','-n','-u','postgres','createdb',name);created=True
        run('sudo','-n','-u','postgres','psql','-d',name,'-v','ON_ERROR_STOP=1','-q',input=options['sql'],stdout=subprocess.DEVNULL)
        run('sudo','-n','-u','postgres','env','TEST_DATABASE='+name,'TEST_API='+options['roles']['neural_api'],
            'FIREBASE_PROJECT_ID=star-galeri','node',str(folder/'verify.mjs'))
    finally:
        if created:run('sudo','-n','-u','postgres','dropdb','--force',name)
        for role in [options['roles'][v] for v in ['neural_api','neural_writer','neural_sync','neural_service']]:
            run('sudo','-n','-u','postgres','psql','-d','postgres','-q','-c','DROP ROLE IF EXISTS '+role)
        shutil.rmtree(folder)
        print('Isolated database, roles and temporary source files removed.')
"""
options={'nonce':nonce,'roles':roles,'archive':base64.b64encode(archive.getvalue()).decode(),'sql':sql,'test':test}
execute(script+'\ncheck('+repr(options)+')\n',timeout=240)
