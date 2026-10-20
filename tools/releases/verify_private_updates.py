"""Live private update verification with one temporary account, cleaned finally.
Never prints or persists credentials, Firebase tokens, or private download URLs.
"""
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid
import requests
from google.auth import jwt
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.admin.firebase_config import PROJECT_ID, admin_key_path, admin_session

def main():
    try:
        credentials = service_account.Credentials.from_service_account_file(str(admin_key_path()), scopes=['https://www.googleapis.com/auth/cloud-platform'])
    except FileNotFoundError:
        credentials = None
    admin = admin_session()
    base = f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents'
    config = json.loads((ROOT/'flutter_application_1/android/app/google-services.json').read_text())
    api_key = config['client'][0]['api_key'][0]['current_key']
    r = admin.get(f'{base}/config/wakeup', timeout=30)
    r.raise_for_status()
    fields = r.json()['fields']
    assert fields['enabled']['booleanValue'] is True
    endpoint = fields['endpoint']['stringValue'].rstrip('/')
    from urllib.parse import urlparse
    parsed = urlparse(endpoint)
    assert parsed.scheme == 'https' and parsed.hostname.endswith('.workers.dev')
    endpoint = f'{parsed.scheme}://{parsed.netloc}'
    for route in ['/updates/latest','/updates/apk']:
        assert requests.get(endpoint+route, timeout=30).status_code == 401
    print('PASS: unauthenticated metadata and APK requests denied.')
    uid = 'private_update_check_' + uuid.uuid4().hex
    grant = f'{base}/updateAccess/{uid}'
    id_token = None
    grant_created = False
    try:
        now = int(time.time())
        if credentials is not None:
            custom = jwt.encode(credentials.signer, {'iss':credentials.service_account_email,'sub':credentials.service_account_email,
                'aud':'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
                'iat':now,'exp':now+300,'uid':uid}).decode()
            r = requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken',
                params={'key':api_key},json={'token':custom,'returnSecureToken':True},timeout=30)
            r.raise_for_status()
        else:
            r = requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signUp', params={'key':api_key}, json={'returnSecureToken':True},timeout=30)
            r.raise_for_status()
            uid = r.json()['localId']
            grant = f'{base}/updateAccess/{uid}'
        id_token = r.json()['idToken']
        headers = {'Authorization':'Bearer '+id_token}
        assert requests.get(endpoint+'/updates/latest',headers=headers,timeout=30).status_code == 403
        assert requests.get(endpoint+'/updates/apk',headers=headers,timeout=30).status_code == 403
        # The application cannot grant itself access or read the backing metadata.
        assert requests.patch(grant,headers=headers,json={'fields':{'enabled':{'booleanValue':True}}},timeout=30).status_code == 403
        assert requests.get(f'{base}/config/private_app_version',headers=headers,timeout=30).status_code == 403
        print('PASS: unapproved account denied; self-grant and direct private metadata denied.')
        r = admin.patch(grant,params={'currentDocument.exists':'false'},json={'fields':{'enabled':{'booleanValue':True}}},timeout=30)
        r.raise_for_status()
        grant_created = True
        r = requests.get(endpoint+'/updates/latest',headers=headers,timeout=30)
        assert r.status_code == 200, f'Private metadata HTTP {r.status_code}'
        data = r.json()
        report = json.loads((ROOT/'artifacts/releases'/data['name']/'build-report.json').read_text(encoding='utf-8-sig'))
        assert data['code'] == report['code'] and data['sha256'] == report['sha256']
        assert urlparse(data['url']).netloc == parsed.netloc
        assert r.headers.get('Cache-Control') == 'no-store'
        digest = hashlib.sha256()
        size = 0
        with requests.get(data['url'],headers=headers,stream=True,allow_redirects=False,timeout=60) as download:
            if download.status_code != 200:
                detail = download.json().get('code','service-error')
                assert False, f'Private APK HTTP {download.status_code}, code: {detail}'
            assert 'Location' not in download.headers
            assert download.headers.get('Cache-Control') == 'private, no-store'
            for chunk in download.iter_content(1024*1024):
                digest.update(chunk)
                size += len(chunk)
        assert digest.hexdigest() == report['sha256'] and size == report['bytes']
        print(f'PASS: authorized APK {data["name"]} streamed and SHA-256/size verified.')
    finally:
        if grant_created:
            r = admin.delete(grant,timeout=30)
            r.raise_for_status()
        if id_token:
            r = requests.post('https://identitytoolkit.googleapis.com/v1/accounts:delete',params={'key':api_key},json={'idToken':id_token},timeout=30)
            r.raise_for_status()
        print('Temporary verification account and grant cleaned.')

if __name__ == '__main__': main()
