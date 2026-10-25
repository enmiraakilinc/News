"""Test media extension over HTTPS with disposable users and three tiny rows."""
import json,sys,uuid
from datetime import datetime,timezone,timedelta
from pathlib import Path
import requests
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.releases.primary_cutover import sql
config=json.loads((ROOT/'flutter_application_1/android/app/google-services.json').read_text(encoding='utf-8'))
key=config['client'][0]['api_key'][0]['current_key'];accounts=[];paths=[]
identity='https://identitytoolkit.googleapis.com/v1/';base='https://138.2.185.151'
q=lambda value:"'"+value.replace("'","''")+"'"
stamp=lambda value:{'timestampValue':value.isoformat().replace('+00:00','Z')}
text=lambda value:{'stringValue':value}
try:
 for _ in range(2):
  r=requests.post(identity+'accounts:signUp',params={'key':key},json={'returnSecureToken':True},timeout=20);r.raise_for_status();accounts.append(r.json())
 own,peer=accounts;nonce='expiry_probe_'+uuid.uuid4().hex;media='chatMedia/'+nonce
 created=datetime.now(timezone.utc)-timedelta(days=1);expiry=created+timedelta(days=2);until=created+timedelta(days=8)
 rows={
  'chats/'+nonce:{'members':{'arrayValue':{'values':[text(own['localId']),text(peer['localId'])]}}},
  media:{'owner':text(own['localId']),'chatId':text(nonce),'coupleId':{'nullValue':None},'kind':text('photo'),'name':text('probe.jpg'),
    'createdAt':stamp(created),'ready':{'booleanValue':True},'size':{'integerValue':'3'},'chunks':{'integerValue':'1'}},
  media+'/chunks/0':{'bytes':{'bytesValue':'AQID'}},
 }
 paths=list(rows);values=[]
 for path,fields in rows.items():
  p=path.split('/');values.append('('+','.join(q(v) for v in [path,'/'.join(p[:-1]),p[-2],p[-1],json.dumps({'fields':fields})])+"::jsonb,'postgres')")
 sql('INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document,origin) VALUES '+','.join(values)+';')
 def commit(account,operations):
  return requests.post(base+'/v1/commit',headers={'Authorization':'Bearer '+account['idToken']},json={'requestId':str(uuid.uuid4()),'operations':operations},timeout=20)
 permission='mediaDownloadRequests/'+nonce+'_'+peer['localId'];paths.append(permission)
 r=commit(peer,[{'type':'set','path':permission,'fields':{'mediaId':text(nonce),'ownerUid':text(own['localId']),
  'requesterUid':text(peer['localId']),'sourceKey':text('chat/'+nonce),'status':text('pending'),
  'requestedAt':{'transformValue':{'operation':'serverTimestamp'}},'expiresAt':stamp(expiry)}}]);r.raise_for_status()
 extension=[{'type':'update','path':media,'fields':[{'field':['expiresAt'],'value':stamp(until)}]},
  {'type':'update','path':permission,'fields':[{'field':['expiresAt'],'value':stamp(until)}]}]
 assert commit(peer,extension).status_code==403
 r=commit(own,extension);r.raise_for_status()
 assert commit(own,[{'type':'delete','path':media+'/chunks/0'},{'type':'delete','path':media}]).status_code==403
 r=requests.post(base+'/v1/read',headers={'Authorization':'Bearer '+peer['idToken']},json={'kind':'documents','paths':[media+'/chunks/0']},timeout=20);r.raise_for_status();assert len(r.json()['rows'])==1
 r=commit(own,[{'type':'update','path':media,'fields':[{'field':['deleteRequestedAt'],'value':{'transformValue':{'operation':'serverTimestamp'}}}]}]);r.raise_for_status()
 r=commit(own,[{'type':'delete','path':media+'/chunks/0'},{'type':'delete','path':media}]);r.raise_for_status()
 print(json.dumps({'liveMediaExtensionVerified':True,'recipientCannotExtend':True,'oldCleanupBlocked':True,'downloadConsentExtendedAtomically':True,'explicitSenderDeleteWorks':True,'realUserMediaModified':False}))
finally:
 if paths:sql('DELETE FROM neural.documents WHERE path IN ('+','.join(q(p) for p in paths)+');')
 if accounts:sql('DELETE FROM neural.commit_receipts WHERE uid IN ('+','.join(q(a['localId']) for a in accounts)+');')
 for a in accounts:
  requests.post(identity+'accounts:delete',params={'key':key},json={'idToken':a['idToken']},timeout=20).raise_for_status()
 print('Disposable media fixtures and accounts removed.')
