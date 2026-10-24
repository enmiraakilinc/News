"""Run compiled API queries with real PostgreSQL RLS inside a rolled-back fixture."""
from pathlib import Path
import json,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute
parent='couples/__compiled_query_probe/letters'
uid='__compiled_query_owner'
t={'timestampValue':'2026-10-24T10:00:00.000000000Z'}
queries=[
 {'name':'equal_timestamp_different_precision','query':{'path':parent,'filters':[{'field':['createdAt'],'op':'==','value':t}]},'count':False,'expected':['a','b']},
 {'name':'numeric_comparison','query':{'path':parent,'filters':[{'field':['n'],'op':'>=','value':{'integerValue':'2'}}]},'count':False,'expected':['b','c']},
 {'name':'descending_cursor_tie','query':{'path':parent,'orders':[{'field':['createdAt'],'descending':True}],'startAfter':[t,{'stringValue':parent+'/b'}],'limit':2},'count':False,'expected':['a']},
 {'name':'count_with_limit','query':{'path':parent,'limit':2},'count':True,'expected':2},
 {'name':'string_order','query':{'path':parent,'orders':[{'field':['title'],'descending':False}]},'count':False,'expected':['a','b','c']},
]
js="import {compileQuery} from './server/src/query.mjs';\nconst input="+json.dumps(queries)+";\nconsole.log(JSON.stringify(input.map(t=>({...t,sql:compileQuery(t.query,"+json.dumps(uid)+",{count:t.count})}))));"
compiled=json.loads(subprocess.check_output(['node','--input-type=module','-'],input=js,text=True,cwd=ROOT))
node=r"""
import pg from 'pg';
const cases=CASES, parent=PARENT, uid=UID;
const db=new pg.Client({host:'/var/run/postgresql',database:'neural_haber',user:'postgres'});
await db.connect();
const insert=async(path,fields)=>{
 const parts=path.split('/');
 await db.query('INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document) VALUES($1,$2,$3,$4,$5::jsonb)',[path,parts.slice(0,-1).join('/'),parts.at(-2),parts.at(-1),JSON.stringify({fields})]);
};
try {
 await db.query('BEGIN');
 await insert('couples/__compiled_query_probe',{members:{arrayValue:{values:[{stringValue:uid}]}}});
 for(const [index,id] of ['a','b','c'].entries()){
  await insert(parent+'/'+id,{
   createdAt:{timestampValue:index===0?'2026-10-24T10:00:00.000000Z':index===1?'2026-10-24T10:00:00Z':'2026-10-24T10:00:00.001Z'},
   n:{integerValue:String(index+1)},title:{stringValue:id}
  });
 }
 await db.query('SET LOCAL ROLE neural_api');
 await db.query("SELECT set_config('neural.uid',$1,true)",[uid]);
 for(const t of cases){
  const result=await db.query(t.sql);
  const actual=t.count?result.rows[0].count:result.rows.map(r=>r.path.split('/').at(-1));
  if(JSON.stringify(actual)!==JSON.stringify(t.expected))throw Error('query_assertion_'+t.name);
  console.log(JSON.stringify({test:t.name,passed:true}));
 }
}finally{await db.query('ROLLBACK');await db.end();}
""".replace('CASES',json.dumps(compiled)).replace('PARENT',json.dumps(parent)).replace('UID',json.dumps(uid))
remote="import subprocess\nr=subprocess.run(['sudo','-n','-u','postgres','node','--input-type=module','-'],input="+repr(node)+",text=True,cwd='/opt/neural/server',check=True)\n"
execute(remote,timeout=90)
