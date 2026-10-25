"""Disposable HTTPS binary transfer/peer isolation benchmark; no real media."""
import base64,hashlib,json,os,sys,time,uuid
from datetime import datetime,timezone
from pathlib import Path
import requests
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from tools.releases.primary_cutover import sql,remote
config=json.loads((ROOT/'flutter_application_1/android/app/google-services.json').read_text(encoding='utf-8'))
key=config['client'][0]['api_key'][0]['current_key'];accounts=[];paths=[]
identity='https://identitytoolkit.googleapis.com/v1/';base='https://138.2.185.151';q=lambda v:"'"+v.replace("'","''")+"'"
try:
 for _ in range(3):
  r=requests.post(identity+'accounts:signUp',params={'key':key},json={'returnSecureToken':True},timeout=20);r.raise_for_status();accounts.append(r.json())
 own,peer,outsider=accounts;nonce='binary_probe_'+uuid.uuid4().hex;media='chatMedia/'+nonce
 raw=[os.urandom(460800) for _ in range(4)];stamp=datetime.now(timezone.utc).isoformat().replace('+00:00','Z')
 text=lambda v:{'stringValue':v}
 rows={'chats/'+nonce:{'members':{'arrayValue':{'values':[text(own['localId']),text(peer['localId'])]}}},
  media:{'owner':text(own['localId']),'chatId':text(nonce),'coupleId':{'nullValue':None},'name':text('probe.mp4'),'kind':text('video'),
   'size':{'integerValue':str(sum(map(len,raw)))},'chunks':{'integerValue':'4'},'ready':{'booleanValue':True},'createdAt':{'timestampValue':stamp}},
  **{media+'/chunks/'+str(i):{'bytes':{'bytesValue':base64.b64encode(v).decode()}} for i,v in enumerate(raw)}}
 paths=list(rows);values=[]
 for path,fields in rows.items():
  p=path.split('/');values.append('('+','.join(q(v) for v in [path,'/'.join(p[:-1]),p[-2],p[-1],json.dumps({'fields':fields})])+"::jsonb,'postgres')")
 statement='INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document,origin) VALUES '+','.join(values)+';'
 remote("import subprocess\nsubprocess.run(['sudo','-u','postgres','psql','-Xq','-v','ON_ERROR_STOP=1','-d','neural_haber'],input="+repr(statement)+",text=True,check=True,stdout=subprocess.DEVNULL)\n")
 chunks=[media+'/chunks/'+str(i) for i in range(4)];session=requests.Session()
 header=lambda a:{'Authorization':'Bearer '+a['idToken']}
 started=time.monotonic();old=session.post(base+'/v1/read',headers=header(own),json={'kind':'documents','paths':chunks},timeout=60);old.raise_for_status();old_time=time.monotonic()-started
 started=time.monotonic();new=session.post(base+'/v1/media/chunks',headers=header(own),json={'paths':chunks},timeout=60);new.raise_for_status();new_time=time.monotonic()-started
 packet=new.content;assert packet[:4]==b'NMC1' and int.from_bytes(packet[4:6],'big')==4;offset=6;decoded=[]
 for _ in range(4):
  size=int.from_bytes(packet[offset:offset+4],'big');iv=packet[offset+4];offset+=5
  assert iv==0;decoded.append(packet[offset:offset+size]);offset+=size
 assert offset==len(packet) and hashlib.sha256(b''.join(decoded)).digest()==hashlib.sha256(b''.join(raw)).digest()
 started=time.monotonic();first=session.post(base+'/v1/media/chunks',headers=header(own),json={'paths':chunks[:1]},timeout=30);first.raise_for_status();first_time=time.monotonic()-started
 assert first.content[:6]==b'NMC1\x00\x01' and first.content[11:]==raw[0]
 assert session.post(base+'/v1/media/chunks',headers=header(outsider),json={'paths':chunks},timeout=20).status_code==403
 presence='chatAccounts/'+own['localId']+'/presence/status';paths.append(presence)
 def commit(a,op):
  r=session.post(base+'/v1/commit',headers=header(a),json={'requestId':str(uuid.uuid4()),'operations':[op]},timeout=20);return r
 consent='chatAccounts/'+own['localId']+'/personalConfig/presence';paths.append(consent)
 r=commit(own,{'type':'set','path':consent,'fields':{'peers':{'arrayValue':{'values':[text(peer['localId'])]}}}});r.raise_for_status()
 r=commit(own,{'type':'set','path':presence,'fields':{'enabled':{'booleanValue':True},'lastSeenAt':{'transformValue':{'operation':'serverTimestamp'}}}});r.raise_for_status()
 for a,visible in [(peer,True),(outsider,False)]:
  r=session.post(base+'/v1/read',headers=header(a),json={'kind':'document','path':presence},timeout=20);r.raise_for_status();assert (r.json()['row'] is not None)==visible
 sql("UPDATE neural.documents SET document=jsonb_set(document,'{fields,lastSeenAt}',jsonb_build_object('timestampValue',to_char((now() AT TIME ZONE 'UTC')-interval '1 minute','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'))) WHERE path="+q(presence))
 before=int(sql('SELECT count(*) FROM neural.commit_receipts WHERE uid='+q(own['localId'])))
 pulse=session.post(base+'/presence',headers=header(own),json={},timeout=20);pulse.raise_for_status();assert pulse.json()['recorded'] is True
 assert int(sql('SELECT count(*) FROM neural.commit_receipts WHERE uid='+q(own['localId'])))==before
 r=commit(own,{'type':'set','path':presence,'fields':{'enabled':{'booleanValue':False}}});r.raise_for_status()
 assert commit(own,{'type':'update','path':presence,'fields':[{'field':['lastSeenAt'],'value':{'transformValue':{'operation':'serverTimestamp'}}}]}).status_code==403
 pulse=session.post(base+'/presence',headers=header(own),json={},timeout=20);pulse.raise_for_status();assert pulse.json()['recorded'] is False
 result={'binaryExactBytesVerified':True,'outsiderMediaBlocked':True,'presencePeerIsolationVerified':True,'presenceOptOutVerified':True,
   'jsonResponseBytes':len(old.content),'binaryResponseBytes':len(packet),'jsonSeconds':round(old_time,3),'binarySeconds':round(new_time,3),
   'firstVideoPieceBytes':len(first.content),'firstVideoPieceSeconds':round(first_time,3),'presenceDoesNotAccumulateReceipts':True,'realUserMediaRead':False}
 (ROOT/'private/media-performance-proof.json').write_text(json.dumps(result,indent=2))
 print(json.dumps(result))
finally:
 if paths:sql('DELETE FROM neural.documents WHERE path IN ('+','.join(q(p) for p in paths)+');')
 if accounts:sql('DELETE FROM neural.commit_receipts WHERE uid IN ('+','.join(q(a['localId']) for a in accounts)+');')
 for a in accounts:requests.post(identity+'accounts:delete',params={'key':key},json={'idToken':a['idToken']},timeout=20).raise_for_status()
 print('Disposable performance fixtures and accounts removed.')
