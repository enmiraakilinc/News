"""Exercise deployed rules with isolated synthetic users; remove fixtures finally."""
import base64
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import time
import uuid
import secrets
import hashlib
import requests
from google.auth import jwt
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from firebase_config import PROJECT_ID, admin_key_path

c = service_account.Credentials.from_service_account_file(str(admin_key_path()), scopes=['https://www.googleapis.com/auth/cloud-platform'])
c.refresh(Request())
admin = requests.Session()
admin.headers['Authorization'] = 'Bearer ' + c.token
root = f'projects/{PROJECT_ID}/databases/(default)/documents'
base = 'https://firestore.googleapis.com/v1/' + root
config = json.loads(Path('flutter_application_1/android/app/google-services.json').read_text())
api_key = config['client'][0]['api_key'][0]['current_key']
prefix = 'media_test_' + uuid.uuid4().hex[:10]
paths = []
tokens = []
def stamp(dt): return {'timestampValue': dt.isoformat()}
def string(v): return {'stringValue': v}
def integer(v): return {'integerValue': str(v)}
def nullable(): return {'nullValue': None}
def array(items): return {'arrayValue': {'values': [string(item) for item in items]}}
def checked(r, status=200):
    assert r.status_code == status, f'Expected {status}, got {r.status_code}: {r.text[:500]}'
    return r
def put(session, path, fields, expected=200):
    if path not in paths: paths.append(path)
    return checked(session.patch(base + '/' + path, json={'fields': fields}, timeout=30), expected)
def commit(session, writes):
    return checked(session.post(base + ':commit', json={'writes': writes}, timeout=30))

try:
    clients = []
    for n in range(3):
        uid = prefix + '_' + str(n)
        now = int(time.time())
        custom = jwt.encode(c.signer, {'iss': c.service_account_email, 'sub': c.service_account_email,
            'aud': 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
            'iat': now, 'exp': now+3600, 'uid': uid}).decode()
        r = checked(requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken',
            params={'key': api_key}, json={'token': custom, 'returnSecureToken': True}, timeout=30))
        token = r.json()['idToken']; tokens.append(token)
        session = requests.Session(); session.headers['Authorization'] = 'Bearer ' + token
        clients.append((uid, session))
        put(session, 'chatProfiles/' + uid, {'name': string('Synthetic ' + str(n))})
    (owner, a), (peer, b), (stranger, outsider) = clients
    # Stars are private to one account and never store message contents.
    source_key = 'chat/' + prefix
    star_id = hashlib.sha256((source_key + '/message').encode()).hexdigest()
    star_path = 'chatAccounts/' + owner + '/starredMessages/' + star_id
    paths.append(star_path)
    commit(a, [{'update': {'name': root + '/' + star_path, 'fields': {
        'sourceKey': string(source_key), 'messageId': string('message')}},
        'updateTransforms': [{'fieldPath': 'starredAt', 'setToServerValue': 'REQUEST_TIME'}]}])
    checked(a.get(base + '/' + star_path, timeout=30))
    checked(b.get(base + '/' + star_path, timeout=30), 403)
    checked(outsider.get(base + '/' + star_path, timeout=30), 403)
    checked(b.delete(base + '/' + star_path, timeout=30), 403)
    checked(a.patch(base + '/' + star_path, params={'updateMask.fieldPaths': 'text'},
        json={'fields': {'text': string('Must not store message contents')}}, timeout=30), 403)
    checked(a.post(base + '/chatAccounts/' + owner + ':runQuery', json={'structuredQuery': {
        'from': [{'collectionId': 'starredMessages'}], 'where': {'fieldFilter': {
            'field': {'fieldPath': 'sourceKey'}, 'op': 'EQUAL', 'value': string(source_key)}}}}, timeout=30))
    checked(a.delete(base + '/' + star_path, timeout=30))
    print('PASS: personal star create/read/query/delete allowed; peer/outsider access and message content storage denied.')
    chat = prefix
    put(admin, 'chats/' + chat, {'members': array([owner, peer]), 'names': {'mapValue': {'fields': {owner: string('A'), peer: string('B')}}}, 'group': {'booleanValue': False}, 'title': string(''), 'createdBy': string(owner), 'updatedAt': stamp(datetime.now(timezone.utc))})
    media = prefix + '_file'
    def metadata(size=550000, ready=False, created=None):
        return {'owner': string(owner), 'chatId': string(chat), 'coupleId': nullable(),
            'name': string('synthetic.bin'), 'kind': string('file'), 'size': integer(size),
            'chunks': integer((size+460799)//460800), 'ready': {'booleanValue': ready},
            **({'createdAt': stamp(created)} if created else {})}
    def create_media(path, size=550000, expected=200, kind='file'):
        paths.append(path)
        r = a.post(base + ':commit', json={'writes': [{'update': {'name': root + '/' + path, 'fields': {**metadata(size), 'kind': string(kind)}},
            'updateTransforms': [{'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'}]}]}, timeout=30)
        checked(r, expected)
    create_media('chatMedia/' + media)
    payload = bytes(range(256)) * 1800  # 450 KiB, above the old 400 KiB limit.
    put(a, 'chatMedia/' + media + '/chunks/0', {'bytes': {'bytesValue': base64.b64encode(payload).decode()}})
    put(a, 'chatMedia/' + media + '/chunks/01', {'bytes': {'bytesValue': 'YQ=='}}, 403)
    put(a, 'chatMedia/' + media + '/chunks/2', {'bytes': {'bytesValue': 'YQ=='}}, 403)
    put(outsider, 'chatMedia/' + media + '/chunks/1', {'bytes': {'bytesValue': 'YQ=='}}, 403)
    checked(b.get(base + '/chatMedia/' + media + '/chunks/0', timeout=30), 403)
    checked(a.patch(base + '/chatMedia/' + media, params={'updateMask.fieldPaths': 'ready'}, json={'fields': {'ready': {'booleanValue': True}}}, timeout=30))
    downloaded = checked(b.get(base + '/chatMedia/' + media + '/chunks/0', timeout=30)).json()
    assert base64.b64decode(downloaded['fields']['bytes']['bytesValue']) == payload
    checked(outsider.get(base + '/chatMedia/' + media, timeout=30), 403)
    checked(outsider.get(base + '/chatMedia/' + media + '/chunks/0', timeout=30), 403)
    immediate_path = 'chats/' + chat + '/messages/immediate_test'
    paths.append(immediate_path)
    fields = {'sender': string(owner), 'text': string('Synthetic immediate message'), 'scheduled': {'booleanValue': False}, 'readBy': array([owner]), 'replyTo': nullable()}
    commit(a, [{'update': {'name': root + '/' + immediate_path, 'fields': fields},
        'updateTransforms': [{'fieldPath': field, 'setToServerValue': 'REQUEST_TIME'} for field in ['sentAt', 'openAt']]}])
    received = checked(b.get(base + '/' + immediate_path, timeout=30)).json()['fields']
    assert received['openAt'] == received['sentAt']
    invalid_path = 'chats/' + chat + '/messages/false_immediate_test'
    paths.append(invalid_path)
    checked(a.post(base + ':commit', json={'writes': [{'update': {'name': root + '/' + invalid_path,
        'fields': {**fields, 'openAt': stamp(datetime.now(timezone.utc) + timedelta(days=1))}},
        'updateTransforms': [{'fieldPath': 'sentAt', 'setToServerValue': 'REQUEST_TIME'}]}]}, timeout=30), 403)
    # The size boundary is also enforced by the backend, not only the UI.
    create_media('chatMedia/' + prefix + '_20mb', 20*1024*1024)
    large = 'chatMedia/' + prefix + '_80mb'
    create_media(large, 80*1024*1024)
    put(a, large + '/chunks/182', {'bytes': {'bytesValue': 'YQ=='}})
    put(a, large + '/chunks/183', {'bytes': {'bytesValue': 'YQ=='}}, 403)
    create_media('chatMedia/' + prefix + '_too_big', 80*1024*1024+1, 403)
    create_media('chatMedia/' + prefix + '_video', 20*1024*1024, kind='video')
    create_media('chatMedia/' + prefix + '_video_too_big', 20*1024*1024+1, 403, kind='video')
    create_media('chatMedia/' + prefix + '_photo_too_big', 20*1024*1024+1, 403, kind='photo')
    expired = datetime.now(timezone.utc) - timedelta(days=2, seconds=10)
    checked(admin.patch(base + '/chatMedia/' + media, params={'updateMask.fieldPaths': 'createdAt'}, json={'fields': {'createdAt': stamp(expired)}}, timeout=30))
    checked(b.get(base + '/chatMedia/' + media + '/chunks/0', timeout=30), 403)
    checked(b.delete(base + '/chatMedia/' + media + '/chunks/0', timeout=30))
    # Videos again expire after 48 hours; earlier videos still play normally.
    video_path = 'chatMedia/' + prefix + '_retention_video'
    sixty_hours = datetime.now(timezone.utc) - timedelta(hours=24)
    put(admin, video_path, {**metadata(1, ready=True, created=sixty_hours), 'kind': string('video')})
    put(admin, video_path + '/chunks/0', {'bytes': {'bytesValue': 'YQ=='}})
    checked(b.get(base + '/' + video_path + '/chunks/0', timeout=30))
    checked(b.delete(base + '/' + video_path + '/chunks/0', timeout=30), 403)
    checked(outsider.get(base + '/' + video_path + '/chunks/0', timeout=30), 403)
    checked(a.patch(base + '/' + video_path, params={'updateMask.fieldPaths': 'deleteRequestedAt'},
        json={'fields': {'deleteRequestedAt': stamp(datetime.now(timezone.utc))}}, timeout=30), 403)
    commit(a, [{'update': {'name': root + '/' + video_path, 'fields': {}},
        'updateMask': {'fieldPaths': []},
        'updateTransforms': [{'fieldPath': 'deleteRequestedAt', 'setToServerValue': 'REQUEST_TIME'}]}])
    checked(a.delete(base + '/' + video_path + '/chunks/0', timeout=30))
    # Expired video becomes inaccessible and can be cleaned by either member.
    expired_video_path = 'chatMedia/' + prefix + '_retention_expired_video'
    put(admin, expired_video_path, {**metadata(1, ready=True,
        created=datetime.now(timezone.utc)-timedelta(hours=49)), 'kind': string('video')})
    put(admin, expired_video_path + '/chunks/0', {'bytes': {'bytesValue': 'YQ=='}})
    checked(b.get(base + '/' + expired_video_path + '/chunks/0', timeout=30), 403)
    checked(b.delete(base + '/' + expired_video_path + '/chunks/0', timeout=30))
    checked(outsider.get(base + '/chatMedia/1ZC95xAZQPrUbOocOM7E', timeout=30), 403)
    print('PASS: 24h video readable, explicit deletion allowed, 49h video denied and peer cleanup allowed; known missing video remains denied to outsiders.')
    # Queries used by the app cleanup must be authorized as well.
    for field, value in [('owner', owner), ('chatId', chat)]:
        checked(a.post(base + ':runQuery', json={'structuredQuery': {'from': [{'collectionId': 'chatMedia'}], 'where': {'fieldFilter': {'field': {'fieldPath': field}, 'op': 'EQUAL', 'value': string(value)}}}}, timeout=30))
    # Secret-space access remains forbidden to a chat-only outsider.
    private = prefix + '_private'
    put(admin, 'couples/' + private, {'members': array([owner]), 'secretCheck': string('synthetic')})
    checked(b.get(base + '/couples/' + private, timeout=30), 403)
    # A valid server-timed invite works even if the generating phone is a day slow.
    code = str(secrets.randbelow(100000000)).zfill(8)
    invite_path = 'chatInvites/' + code
    paths.append(invite_path)
    commit(a, [{'update': {'name': root + '/' + invite_path, 'fields': {
        'owner': string(owner), 'name': string('Synthetic 0'), 'usedBy': nullable(),
        'expiresAt': stamp(datetime.now(timezone.utc) - timedelta(days=1))}},
        'updateTransforms': [{'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'}]}])
    direct = 'direct_' + '_'.join(sorted([owner, peer]))
    paths.append('chats/' + direct)
    checked(b.get(base + '/chats/' + direct, timeout=30), 404)
    writes = [
        {'update': {'name': root + '/' + invite_path, 'fields': {'usedBy': string(peer)}}, 'updateMask': {'fieldPaths': ['usedBy']}},
        {'update': {'name': root + '/chats/' + direct, 'fields': {
            'members': array([owner, peer]), 'names': {'mapValue': {'fields': {owner: string('Synthetic 0'), peer: string('Synthetic 1')}}},
            'group': {'booleanValue': False}, 'title': string(''), 'createdBy': string(peer), 'inviteCode': string(code)}},
            'updateTransforms': [{'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'}]},
    ]
    commit(b, writes)
    checked(a.get(base + '/chats/' + direct, timeout=30))
    checked(b.get(base + '/chats/' + direct, timeout=30))
    checked(outsider.patch(base + '/' + invite_path, params={'updateMask.fieldPaths': 'usedBy'}, json={'fields': {'usedBy': string(stranger)}}, timeout=30), 403)
    checked(admin.patch(base + '/' + invite_path, params=[('updateMask.fieldPaths', 'createdAt'), ('updateMask.fieldPaths', 'usedBy')], json={'fields': {'usedBy': nullable(), 'createdAt': stamp(datetime.now(timezone.utc)-timedelta(hours=2))}}, timeout=30))
    checked(b.patch(base + '/' + invite_path, params={'updateMask.fieldPaths': 'usedBy'}, json={'fields': {'usedBy': string(peer)}}, timeout=30), 403)
    print('PASS: clock-skewed invite creates a shared chat; used and expired codes rejected.')
    print('PASS: chunk transfer, 80 MiB files / 20 MiB media boundaries, chunk 182, nonmember/incomplete/expired denial, canonical chunks, peer cleanup, metadata queries, private-space isolation.')
finally:
    for path in reversed(paths):
        r = admin.delete(base + '/' + path, timeout=30)
        r.raise_for_status()
    for token in tokens:
        r = requests.post('https://identitytoolkit.googleapis.com/v1/accounts:delete', params={'key': api_key}, json={'idToken': token}, timeout=30)
        r.raise_for_status()
    print('Synthetic documents and accounts removed.')
