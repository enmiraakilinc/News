"""Probe with disposable users and owner-only fixtures; no real chats modified."""
from pathlib import Path
import concurrent.futures,json,queue,sys,time,threading
import requests
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.admin.firebase_config import admin_session
info=json.loads((ROOT/'flutter_application_1/android/app/google-services.json').read_text())
API_KEY=info['client'][0]['api_key'][0]['current_key']
PROJECT=info['project_info']['project_id']
BASE='https://138.2.185.151'
FIRESTORE='https://firestore.googleapis.com/v1/projects/'+PROJECT+'/databases/(default)/documents/'
accounts=[]
def checked(response):
    if not response.ok:raise RuntimeError('Request failed '+str(response.status_code)+' (body withheld)')
    return response.json()
def signup():
    data=checked(requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signUp',params={'key':API_KEY},json={'returnSecureToken':True},timeout=20))
    account={'uid':data['localId'],'token':data['idToken']}
    accounts.append(account);return account
def headers(account):return {'Authorization':'Bearer '+account['token']}
def read(account,path):
    return checked(requests.post(BASE+'/v1/read',headers=headers(account),json={'kind':'document','path':path},timeout=15))
def wait_value(account,path,value):
    deadline=time.monotonic()+20
    while time.monotonic()<deadline:
        row=read(account,path)['row']
        actual=None if row is None else row['document']['fields']['alias']['stringValue']
        if actual==value:return row
        time.sleep(.3)
    raise RuntimeError('Mirror deadline exceeded; content withheld')
def fixture(account,path,text):
    checked(requests.patch(FIRESTORE+path,headers=headers(account),json={'fields':{'alias':{'stringValue':text},'hidden':{'booleanValue':False}}},timeout=20))
def delete_fixture(path):
    assert accounts and path=='chatAccounts/'+accounts[0]['uid']+'/contacts/__migration_probe'
    result=admin_session().delete(FIRESTORE+path,timeout=20)
    assert result.status_code in (200,404)
def observed_event(events,value):
    deadline=time.monotonic()+12
    while time.monotonic()<deadline:
        event=events.get(timeout=max(.1,deadline-time.monotonic()))
        if event==value:return
    raise RuntimeError('Expected SSE update did not arrive')
def stream(account,path,events,stopped):
    try:
        with requests.post(BASE+'/v1/watch',headers=headers(account),json={'kind':'document','path':path},stream=True,timeout=(10,15)) as response:
            if not response.ok:raise RuntimeError('watch_http_'+str(response.status_code))
            for line in response.iter_lines(chunk_size=1):
                if stopped.is_set():break
                if line.startswith(b'data: '):
                    data=json.loads(line[6:]);row=data.get('row')
                    events.put(None if row is None else row['document']['fields']['alias']['stringValue'])
                    if events.qsize()>10:break
    except Exception as e:
        if not stopped.is_set():events.put('error:'+type(e).__name__)
fixture_path=None
stopped=threading.Event()
try:
    a,b=signup(),signup()
    fixture_path='chatAccounts/'+a['uid']+'/contacts/__migration_probe'
    assert read(a,fixture_path)['row'] is None
    events=queue.Queue()
    thread=threading.Thread(target=stream,args=(a,fixture_path,events,stopped),daemon=True)
    thread.start()
    assert events.get(timeout=15) is None
    fixture(a,fixture_path,'migration-probe-one')
    first=wait_value(a,fixture_path,'migration-probe-one')
    assert read(b,fixture_path)['row'] is None
    forbidden=requests.post(BASE+'/v1/read',headers=headers(b),json={'kind':'query','query':{'path':'chatAccounts/'+a['uid']+'/contacts'}},timeout=15)
    assert forbidden.status_code==403
    own=checked(requests.post(BASE+'/v1/read',headers=headers(a),json={'kind':'query','query':{'path':'chatAccounts/'+a['uid']+'/contacts'}},timeout=15))
    assert len(own['rows'])==1
    observed_event(events,'migration-probe-one')
    fixture(a,fixture_path,'migration-probe-two')
    second=wait_value(a,fixture_path,'migration-probe-two')
    assert first['version']!=second['version']
    observed_event(events,'migration-probe-two')
    # Existing contact rules intentionally use hidden=true instead of allowing
    # client physical deletion. Remove ONLY this run's fixture with local admin.
    delete_fixture(fixture_path)
    wait_value(a,fixture_path,None)
    observed_event(events,None)
    stopped.set()
    print(json.dumps({'trustedHttps':True,'validFirebaseSessionVerified':True,'mirrorCreateUpdateDeletePassed':True,'revisionChanged':True,'sseCreateUpdateDeletePassed':True,'crossAccountReadBlocked':True,'crossAccountQueryBlocked':True,'realChatsModified':False}))
finally:
    stopped.set()
    if fixture_path and accounts:
        delete_fixture(fixture_path)
    for account in accounts:
        r=requests.post('https://identitytoolkit.googleapis.com/v1/accounts:delete',params={'key':API_KEY},json={'idToken':account['token']},timeout=20)
        if not r.ok:print(json.dumps({'cleanupWarning':'temporary_identity_delete_failed','status':r.status_code}))
    print(json.dumps({'temporaryIdentityCleanupAttempted':len(accounts)}))
