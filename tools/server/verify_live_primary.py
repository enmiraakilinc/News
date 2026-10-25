"""HTTPS primary read/write, SSE and isolation checks with disposable users."""
import json,sys,uuid
from pathlib import Path
import requests
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.releases.primary_cutover import sql

def main():
    config=json.loads((ROOT/'flutter_application_1/android/app/google-services.json').read_text())
    key=config['client'][0]['api_key'][0]['current_key']
    identity='https://identitytoolkit.googleapis.com/v1/'
    base='https://138.2.185.151'
    accounts=[];paths=[]
    try:
        for _ in range(2):
            response=requests.post(identity+'accounts:signUp',params={'key':key},json={'returnSecureToken':True},timeout=20)
            response.raise_for_status();accounts.append(response.json())
        own,other=accounts
        headers=lambda account:{'Authorization':'Bearer '+account['idToken']}
        path='chatAccounts/'+own['localId']+'/personalData/release_probe'
        paths=[path]
        payload={'requestId':str(uuid.uuid4()),'operations':[{'type':'set','path':path,'fields':{
            'kind':{'stringValue':'news'},'cipher':{'stringValue':'disposable verification'},
            'updatedAt':{'transformValue':{'operation':'serverTimestamp'}}}}]}
        def commit(body,account=own):
            return requests.post(base+'/v1/commit',headers=headers(account),json=body,timeout=20)
        first=commit(payload);first.raise_for_status()
        repeated=commit(payload);repeated.raise_for_status();assert first.json()==repeated.json()
        def read(account):
            response=requests.post(base+'/v1/read',headers=headers(account),json={'kind':'document','path':path},timeout=20)
            response.raise_for_status();return response.json()['row']
        assert read(own)['document']['fields']['cipher']['stringValue']=='disposable verification'
        assert read(other) is None
        assert commit({**payload,'requestId':str(uuid.uuid4())},other).status_code==403
        watch=requests.post(base+'/v1/watch',headers=headers(own),json={'kind':'document','path':path},stream=True,timeout=(15,20))
        watch.raise_for_status()
        lines=watch.iter_lines(chunk_size=1)
        def event():
            for line in lines:
                if line.startswith(b'data: '):return json.loads(line[6:])
            raise AssertionError('SSE ended before data')
        assert event()['row']['path']==path
        version=first.json()['versions'][path]
        update={'requestId':str(uuid.uuid4()),'conditions':[{'path':path,'version':version}],
            'operations':[{'type':'update','path':path,'fields':[
                {'field':['cipher'],'value':{'stringValue':'updated probe'}},
                {'field':['updatedAt'],'value':{'transformValue':{'operation':'serverTimestamp'}}}]}]}
        result=commit(update);result.raise_for_status()
        assert event()['row']['document']['fields']['cipher']['stringValue']=='updated probe'
        watch.close()
        assert commit({**update,'requestId':str(uuid.uuid4())}).status_code==409
        denied=requests.patch('https://firestore.googleapis.com/v1/projects/'+config['project_info']['project_id']+
            '/databases/(default)/documents/chatProfiles/'+own['localId'],headers=headers(own),
            json={'fields':{'name':{'stringValue':'write must be denied'}}},timeout=20)
        assert denied.status_code==403,'Legacy writes must remain disabled'
        assert requests.get(base+'/health',timeout=20).json()['mode']=='primary'
        print(json.dumps({'httpsCreateReadUpdate':True,'idempotency':True,'crossAccountBlocked':True,
            'liveSseUpdate':True,'staleTransactionRejected':True,'legacyWritesBlocked':True,
            'realUserMessagesOrPushesSent':False}))
    finally:
        if accounts:
            # Restrict cleanup to the random disposable identities from this run.
            ids=[a['localId'] for a in accounts]
            assert all(uid.isalnum() for uid in ids)
            quoted=','.join("'"+uid+"'" for uid in ids)
            if paths:
                sql("DELETE FROM neural.documents WHERE path='"+paths[0]+"'; DELETE FROM neural.commit_receipts WHERE uid IN ("+quoted+");")
            for account in accounts:
                response=requests.post(identity+'accounts:delete',params={'key':key},json={'idToken':account['idToken']},timeout=20)
                response.raise_for_status()
        print('Disposable primary fixtures and identities removed.')

if __name__=='__main__':main()
