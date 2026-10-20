"""Read attachment references near the requested timestamp, without message contents."""
import json
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession
from firebase_config import PROJECT_ID, admin_key_path
s = AuthorizedSession(service_account.Credentials.from_service_account_file(
    str(admin_key_path()), scopes=['https://www.googleapis.com/auth/cloud-platform']))
base = f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents'
for collection, child, field in [('chats', 'messages', 'sentAt'), ('couples', 'letters', 'createdAt')]:
    r = s.get(base + '/' + collection, params={'pageSize': 1000}, timeout=30); r.raise_for_status()
    for parent in r.json().get('documents', []):
        query = {'from': [{'collectionId': child}], 'where': {'compositeFilter': {'op': 'AND', 'filters': [
            {'fieldFilter': {'field': {'fieldPath': field}, 'op': 'GREATER_THAN_OR_EQUAL', 'value': {'timestampValue': '2026-10-12T21:29:00Z'}}},
            {'fieldFilter': {'field': {'fieldPath': field}, 'op': 'LESS_THAN', 'value': {'timestampValue': '2026-10-12T21:36:00Z'}}},
        ]}}}
        r = s.post('https://firestore.googleapis.com/v1/' + parent['name'] + ':runQuery', json={'structuredQuery': query}, timeout=30); r.raise_for_status()
        for row in r.json():
            if 'document' not in row: continue
            doc = row['document']; fields = doc['fields']
            text = fields.get('text', {}).get('stringValue', '')
            print('Timestamp match:', doc['name'], fields.get(field), 'encrypted' if 'cipher' in fields else 'plain')
            if text.startswith('NEURAL_MEDIA:'):
                media = json.loads(text[len('NEURAL_MEDIA:'):])
                print('Media reference:', media['id'], media.get('kind'))
                r = s.get(base + '/chatMedia/' + media['id'], timeout=30)
                print('Metadata status:', r.status_code)
                r = s.get(base + '/chatMedia/' + media['id'] + '/chunks', params={'pageSize': 1}, timeout=30); r.raise_for_status()
                print('Any chunks remaining:', bool(r.json().get('documents')))
            elif text.startswith('NEURAL_FILE:'):
                print('Legacy inline attachment remains in message.')
