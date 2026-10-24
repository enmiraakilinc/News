"""Exercise VPS extension routes using only disposable identities/PG rows."""
import json, sys, uuid, subprocess
from pathlib import Path
from datetime import datetime, timezone, timedelta
import requests
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute
config=json.loads((ROOT/'flutter_application_1/android/app/google-services.json').read_text(encoding='utf-8'))
key=config['client'][0]['api_key'][0]['current_key']
base='https://138.2.185.151'
accounts=[]
paths=[]
def sql_run(sql):
    code="import subprocess\nsubprocess.run(['sudo','-n','-u','postgres','psql','-d','neural_haber','-v','ON_ERROR_STOP=1','-q'],input="+repr(sql)+",text=True,check=True)\n"
    execute(code,timeout=60)
def quote(value):
    return "'"+value.replace("'","''")+"'"
try:
    for _ in range(2):
        r=requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signUp',
            params={'key':key},json={'returnSecureToken':True},timeout=20)
        r.raise_for_status()
        data=r.json()
        accounts.append({'uid':data['localId'],'token':data['idToken']})
    own,other=accounts
    headers=lambda a:{'Authorization':'Bearer '+a['token']}
    assert requests.get(base+'/storage/status',timeout=15).status_code==401
    r=requests.get(base+'/storage/status',headers=headers(own),timeout=15)
    r.raise_for_status()
    report=r.json()
    assert report['provider']=='oracle' and report['bytes']+report['freeBytes']==report['limitBytes']
    nonce='migration_probe_'+uuid.uuid4().hex
    now=datetime.now(timezone.utc)
    text=lambda v:{'stringValue':v}
    doc=lambda fields:{'fields':fields,'updateTime':now.isoformat().replace('+00:00','Z')}
    chat='chats/'+nonce
    entries=[(chat,doc({'members':{'arrayValue':{'values':[text(own['uid']),text('probe_peer')]}}}))]
    for suffix,age in [('active',0),('expired',3)]:
        root='chatMedia/'+nonce+'_'+suffix
        created=(now-timedelta(days=age)).isoformat().replace('+00:00','Z')
        entries.extend([
            (root,doc({'owner':text(own['uid']),'chatId':text(nonce),'coupleId':{'nullValue':None},
                'ready':{'booleanValue':True},'createdAt':{'timestampValue':created}})),
            (root+'/chunks/0',doc({'bytes':{'bytesValue':'AQID'}})),
        ])
    paths=[p for p,_ in entries]
    values=[]
    for path,document in entries:
        parts=path.split('/')
        values.append('('+','.join(quote(v) for v in [path,'/'.join(parts[:-1]),parts[-2],parts[-1],json.dumps(document)])+'::jsonb)')
    sql_run('INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document) VALUES '+','.join(values)+';')
    for suffix,account,count in [('active',own,1),('active',other,0),('expired',own,0)]:
        path='chatMedia/'+nonce+'_'+suffix+'/chunks/0'
        r=requests.post(base+'/v1/read',headers=headers(account),
            json={'kind':'documents','paths':[path]},timeout=15)
        r.raise_for_status()
        result=r.json()['rows']
        assert len(result)==count
        if result:assert result[0]['document']['fields']['bytes']['bytesValue']=='AQID'
    r=requests.post(base+'/v1/read',headers=headers(own),
        json={'kind':'documents','paths':['chatInvites/12345678']},timeout=15)
    assert r.status_code==400
    print(json.dumps({'storageRequiresSession':True,'oracleDiskReportVerified':True,
        'mediaBatchBytesVerified':True,'crossAccountBatchBlocked':True,
        'expiredBatchBlocked':True,'inviteEnumerationBlocked':True}))
finally:
    if paths:
        sql_run('DELETE FROM neural.documents WHERE path IN ('+','.join(quote(p) for p in paths)+');')
    for account in accounts:
        r=requests.post('https://identitytoolkit.googleapis.com/v1/accounts:delete',
            params={'key':key},json={'idToken':account['token']},timeout=20)
        r.raise_for_status()
    print('Disposable identities and PostgreSQL fixtures cleaned.')
