"""Provision the explicitly approved read-only Firestore mirror identity."""
from pathlib import Path
import base64,getpass,json,os,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.admin.google_owner_session import owner_session
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession
PROJECT='star-galeri'
ACCOUNT='neural-pg-reader'
EMAIL=ACCOUNT+'@'+PROJECT+'.iam.gserviceaccount.com'
PRIVATE=ROOT/'private/server-migration-20261024'
KEY=PRIVATE/'neural-pg-reader.json'
PRIVATE.mkdir(parents=True,exist_ok=True)
session=owner_session()
def request(method,url,**kwargs):
    response=session.request(method,url,timeout=40,**kwargs)
    if not response.ok:
        raise RuntimeError('Google API '+str(response.status_code)+' '+str(response.json().get('error',{}).get('status','unknown')))
    return response.json()
role=request('GET','https://iam.googleapis.com/v1/roles/datastore.viewer')
permissions=role.get('includedPermissions',[])
assert all(p in permissions for p in ['datastore.entities.get','datastore.entities.list'])
assert not any(p in permissions for p in ['datastore.entities.create','datastore.entities.update','datastore.entities.delete'])
account_url='https://iam.googleapis.com/v1/projects/'+PROJECT+'/serviceAccounts/'+EMAIL
exists=session.get(account_url,timeout=30)
if exists.status_code==404:
    request('POST','https://iam.googleapis.com/v1/projects/'+PROJECT+'/serviceAccounts',json={
        'accountId':ACCOUNT,'serviceAccount':{'displayName':'Neural PostgreSQL read-only mirror','description':'Read Firestore into private Oracle PostgreSQL; no write, Auth admin or FCM permission.'}})
    print(json.dumps({'readerAccountCreated':True}))
elif not exists.ok:
    raise RuntimeError('Account lookup failed: '+str(exists.status_code))
policy_url='https://cloudresourcemanager.googleapis.com/v1/projects/'+PROJECT
policy=request('POST',policy_url+':getIamPolicy',json={'options':{'requestedPolicyVersion':3}})
member='serviceAccount:'+EMAIL
existing=[b['role'] for b in policy.get('bindings',[]) if member in b.get('members',[])]
assert all(r=='roles/datastore.viewer' for r in existing),'Reader unexpectedly has another role; refusing key creation.'
if not existing:
    backup=PRIVATE/'iam-policy-before-reader.json'
    if not backup.exists():backup.write_text(json.dumps(policy,indent=2),encoding='utf-8')
    binding=next((b for b in policy.get('bindings',[]) if b['role']=='roles/datastore.viewer' and not b.get('condition')),None)
    if binding is None:
        binding={'role':'roles/datastore.viewer','members':[]}
        policy.setdefault('bindings',[]).append(binding)
    binding['members'].append(member)
    request('POST',policy_url+':setIamPolicy',json={'policy':policy})
confirmed=request('POST',policy_url+':getIamPolicy',json={'options':{'requestedPolicyVersion':3}})
bound=[b['role'] for b in confirmed.get('bindings',[]) if member in b.get('members',[])]
assert bound==['roles/datastore.viewer']
if not KEY.exists():
    created=request('POST',account_url+'/keys',json={'privateKeyType':'TYPE_GOOGLE_CREDENTIALS_FILE','keyAlgorithm':'KEY_ALG_RSA_2048'})
    raw=base64.b64decode(created['privateKeyData'])
    info=json.loads(raw)
    assert info.get('client_email')==EMAIL and info.get('project_id')==PROJECT
    KEY.write_bytes(raw)
    if os.name=='nt':
        user=os.environ.get('USERDOMAIN','')+'\\'+getpass.getuser()
        subprocess.run(['icacls',str(KEY),'/inheritance:r','/grant:r',user+':(F)'],check=True,stdout=subprocess.DEVNULL)
    else:KEY.chmod(0o600)
creds=service_account.Credentials.from_service_account_file(str(KEY),scopes=['https://www.googleapis.com/auth/cloud-platform'])
reader=AuthorizedSession(creds)
wanted=['datastore.entities.get','datastore.entities.list','datastore.entities.create','datastore.entities.update','datastore.entities.delete']
for attempt in range(8):
    response=reader.post(policy_url+':testIamPermissions',json={'permissions':wanted},timeout=30)
    effective=response.json().get('permissions',[]) if response.ok else []
    if all(x in effective for x in wanted[:2]):break
    time.sleep(3)
assert set(effective)==set(wanted[:2]),'Read-only effective role did not validate; mirror must remain disabled.'
print(json.dumps({'effectiveReadAllowed':True,'effectiveCreateUpdateDeleteAllowed':False,'privateKeyPrinted':False,'existingAdminKeyUsedOnVps':False}))
