"""Check real anonymous-account linking, second-device login and contact isolation."""
import json
import secrets
import uuid
from pathlib import Path
import requests
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession
from firebase_config import PROJECT_ID, admin_key_path

c = service_account.Credentials.from_service_account_file(str(admin_key_path()), scopes=['https://www.googleapis.com/auth/cloud-platform'])
admin = AuthorizedSession(c)
config = json.loads(Path('flutter_application_1/android/app/google-services.json').read_text())
key = config['client'][0]['api_key'][0]['current_key']
auth = 'https://identitytoolkit.googleapis.com/v1/accounts:'
root = f'projects/{PROJECT_ID}/databases/(default)/documents'
base = 'https://firestore.googleapis.com/v1/' + root
users = []
paths = []
password = secrets.token_urlsafe(24)
email = uuid.uuid4().hex + '@accounts.neural.invalid'

def call(method, body, success=True):
    r = requests.post(auth + method, params={'key': key}, json=body, timeout=30)
    if success: assert r.ok, f'{method}: status {r.status_code}, {r.json().get("error", {}).get("message", "unknown")}'
    return r

def client(token):
    s = requests.Session(); s.headers['Authorization'] = 'Bearer ' + token
    return s

try:
    first = call('signUp', {'returnSecureToken': True}).json()
    users.append(first['localId'])
    owner = first['localId']
    original = client(first['idToken'])
    peer_data = call('signUp', {'returnSecureToken': True}).json()
    users.append(peer_data['localId'])
    peer = client(peer_data['idToken'])
    chat_id = 'account_test_' + uuid.uuid4().hex
    chat = 'chats/' + chat_id
    paths.append(chat)
    r = admin.patch(base + '/' + chat, json={'fields': {
        'members': {'arrayValue': {'values': [{'stringValue': owner}, {'stringValue': peer_data['localId']}]}},
        'group': {'booleanValue': False}, 'title': {'stringValue': 'Synthetic chat'},
    }}, timeout=30); assert r.ok
    setting = f'chatAccounts/{owner}/contacts/{chat_id}'
    paths.append(setting)
    r = original.patch(base + '/' + setting, json={'fields': {
        'alias': {'stringValue': 'Synthetic contact'}, 'hidden': {'booleanValue': False},
    }}, timeout=30); assert r.ok
    linked = call('signUp', {'idToken': first['idToken'], 'email': email, 'password': password, 'returnSecureToken': True}).json()
    assert linked['localId'] == owner
    signed = call('signInWithPassword', {'email': email, 'password': password, 'returnSecureToken': True}).json()
    assert signed['localId'] == owner
    second = client(signed['idToken'])
    assert second.get(base + '/' + chat, timeout=30).ok
    r = second.get(base + '/' + setting, timeout=30)
    assert r.ok and r.json()['fields']['alias']['stringValue'] == 'Synthetic contact'
    assert peer.get(base + '/' + setting, timeout=30).status_code == 403
    assert peer.patch(base + '/' + setting, json={'fields': {'alias': {'stringValue': 'Unauthorized'}}}, timeout=30).status_code == 403
    r = second.patch(base + '/' + setting, json={'fields': {'alias': {'stringValue': 'Second device name'}, 'hidden': {'booleanValue': True}}}, timeout=30)
    assert r.ok
    assert original.get(base + '/' + setting, timeout=30).json()['fields']['hidden']['booleanValue']
    r = second.post(base + f'/chatAccounts/{owner}:runQuery', json={'structuredQuery': {'from': [{'collectionId': 'contacts'}]}}, timeout=30)
    assert r.ok and any('document' in d for d in r.json())
    assert not call('signInWithPassword', {'email': email, 'password': secrets.token_urlsafe(24), 'returnSecureToken': True}, False).ok
    assert not call('signInWithPassword', {'email': uuid.uuid4().hex + '@accounts.neural.invalid', 'password': password, 'returnSecureToken': True}, False).ok
    # Linking one chat account never enrolls its peer in the private shared area.
    private = 'couples/' + chat_id
    paths.append(private)
    r = admin.patch(base + '/' + private, json={'fields': {'members': {'arrayValue': {'values': [{'stringValue': owner}]}}}}, timeout=30)
    assert r.ok
    assert second.get(base + '/' + private, timeout=30).ok
    assert peer.get(base + '/' + private, timeout=30).status_code == 403
    changed_password = secrets.token_urlsafe(24)
    changed = call('update', {'idToken': signed['idToken'], 'password': changed_password, 'returnSecureToken': True}).json()
    assert changed['localId'] == owner
    assert not call('signInWithPassword', {'email': email, 'password': password, 'returnSecureToken': True}, False).ok
    assert call('signInWithPassword', {'email': email, 'password': changed_password, 'returnSecureToken': True}).json()['localId'] == owner
    print('PASS: linking preserves UID; second-device chats/aliases; owner-only settings; wrong code/password rejected; private area isolation.')
finally:
    for path in reversed(paths):
        r = admin.delete(base + '/' + path, timeout=30)
        assert r.status_code in (200, 404), 'Fixture cleanup failed'
    for uid in users:
        r = admin.post(auth + 'delete', json={'targetProjectId': PROJECT_ID, 'localId': uid}, timeout=30)
        assert r.ok, 'Synthetic account cleanup failed'
    print('Synthetic records and accounts removed.')
