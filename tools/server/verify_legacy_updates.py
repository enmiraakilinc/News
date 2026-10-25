"""Check the legacy private update path without notifying real users."""
import argparse,json,sys
from pathlib import Path
import requests
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.admin.firebase_config import admin_session,PROJECT_ID

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--version',required=True)
    args=parser.parse_args()
    report=json.loads((ROOT/'artifacts/releases'/args.version/'build-report.json').read_text(encoding='utf-8-sig'))
    config=json.loads((ROOT/'flutter_application_1/android/app/google-services.json').read_text(encoding='utf-8'))
    key=config['client'][0]['api_key'][0]['current_key']
    identity='https://identitytoolkit.googleapis.com/v1/'
    result=requests.post(identity+'accounts:signUp',params={'key':key},json={'returnSecureToken':True},timeout=20)
    result.raise_for_status();account=result.json();session=admin_session()
    endpoint=f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/updateAccess/'+account['localId']
    try:
        session.patch(endpoint,json={'fields':{'enabled':{'booleanValue':True}}},timeout=20).raise_for_status()
        response=requests.get('https://neural-wakeup.free-wakeup-worker.workers.dev/updates/latest',
            headers={'Authorization':'Bearer '+account['idToken']},timeout=30)
        response.raise_for_status();metadata=response.json()
        assert metadata['name']==args.version and metadata['code']==report['code'] and metadata['sha256']==report['sha256']
        with requests.get('https://neural-wakeup.free-wakeup-worker.workers.dev/updates/transition/1.14.32.apk',stream=True,timeout=30) as response:
            response.raise_for_status();assert next(response.iter_content(4))[:2]==b'PK'
        print(json.dumps({'legacyPrivateLatestVerified':args.version,'legacyPublicBridgeVerified':True,'realUserNotificationsSent':False}))
    finally:
        session.delete(endpoint,timeout=20).raise_for_status()
        requests.post(identity+'accounts:delete',params={'key':key},json={'idToken':account['idToken']},timeout=20).raise_for_status()

if __name__=='__main__':main()
