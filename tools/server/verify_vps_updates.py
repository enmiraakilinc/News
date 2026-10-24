"""Validate the current private VPS download with a disposable identity only."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
import requests
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute

def fixture(uid,remove=False):
    script='''import json,subprocess
def change(uid,remove):
    assert uid.isalnum()
    path='updateAccess/'+uid
    if remove:sql="DELETE FROM neural.documents WHERE path='"+path+"';"
    else:
        document=json.dumps({'fields':{'enabled':{'booleanValue':True}}})
        sql="INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document,origin) VALUES ('"+path+"','updateAccess','updateAccess','"+uid+"','"+document+"'::jsonb,'postgres');"
    subprocess.run(['sudo','-n','-u','postgres','psql','-Xq','-v','ON_ERROR_STOP=1','-d','neural_haber','-c',sql],check=True,stdout=subprocess.DEVNULL)
'''
    execute(script+'\nchange('+repr(uid)+','+repr(remove)+')\n')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--version',default='1.15.1')
    args=parser.parse_args()
    config=json.loads((ROOT/'flutter_application_1/android/app/google-services.json').read_text(encoding='utf-8'))
    key=config['client'][0]['api_key'][0]['current_key']
    base='https://identitytoolkit.googleapis.com/v1/'
    result=requests.post(base+'accounts:signUp',params={'key':key},json={'returnSecureToken':True},timeout=20)
    result.raise_for_status();identity=result.json();uid=identity['localId'];token=identity['idToken'];created=False
    try:
        endpoint='https://138.2.185.151/updates/latest'
        assert requests.get(endpoint,timeout=20).status_code==401
        headers={'Authorization':'Bearer '+token}
        assert requests.get(endpoint,headers=headers,timeout=20).status_code==403
        fixture(uid);created=True
        response=requests.get(endpoint,headers=headers,timeout=20);response.raise_for_status();metadata=response.json()
        assert metadata['name']==args.version,'Unexpected live update version'
        report=json.loads((ROOT/'artifacts/releases'/args.version/'build-report.json').read_text(encoding='utf-8-sig'))
        assert metadata['sha256']==report['sha256']
        assert 'github' not in json.dumps(metadata).lower()
        digest=hashlib.sha256()
        with requests.get(metadata['url'],headers=headers,stream=True,timeout=60) as download:
            download.raise_for_status()
            for block in download.iter_content(1024*1024):digest.update(block)
        assert digest.hexdigest()==report['sha256']
        print(json.dumps({'vpsPrivateUpdatesVerified':True,'authenticatedDownloadHashVerified':True,'version':args.version,'realUserDataModified':False}))
    finally:
        if created:fixture(uid,True)
        response=requests.post(base+'accounts:delete',params={'key':key},json={'idToken':token},timeout=20)
        response.raise_for_status()
        print('Disposable update access and identity removed.')

if __name__=='__main__':main()
