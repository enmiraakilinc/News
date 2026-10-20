"""Read only the requested Defne screenshot attachments; never print message bodies."""
import base64
import json
import sys
import io
from PIL import Image
from pathlib import Path
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession
from firebase_config import PROJECT_ID, admin_key_path, ROOT

s = AuthorizedSession(service_account.Credentials.from_service_account_file(str(admin_key_path()), scopes=['https://www.googleapis.com/auth/cloud-platform']))
base = f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents'
query = {'from': [{'collectionId': 'contacts', 'allDescendants': True}], 'select': {'fields': [{'fieldPath': 'alias'}]}}
r = s.post(base + ':runQuery', json={'structuredQuery': query}, timeout=30)
r.raise_for_status()
chats = {row['document']['name'].split('/')[-1] for row in r.json() if 'document' in row and 'defne' in row['document'].get('fields', {}).get('alias', {}).get('stringValue', '').lower()}
print('Matching contact chats:', len(chats))
output = ROOT / 'private/backups/requested-screenshot'
output.mkdir(parents=True, exist_ok=True)
for chat in chats:
    query = {'from': [{'collectionId': 'messages'}], 'orderBy': [{'field': {'fieldPath': 'sentAt'}, 'direction': 'DESCENDING'}], 'limit': 400}
    r = s.post(base + '/chats/' + chat + ':runQuery', json={'structuredQuery': query}, timeout=30)
    r.raise_for_status()
    for row in r.json():
        doc = row.get('document', {})
        text = doc.get('fields', {}).get('text', {}).get('stringValue', '')
        if not text.startswith(('NEURAL_FILE:', 'NEURAL_MEDIA:')):
            continue
        data = json.loads(text.split(':', 1)[1])
        name = str(data.get('name', ''))
        if not ('screenshot' in name.lower() and 'instagram' in name.lower()):
            continue
        print('Matching attachment:', name, 'kind:', data.get('kind'), 'fields:', list(data.keys()))
        if text.startswith('NEURAL_FILE:'):
            raw = data.get('bytes')
            print('Inline bytes field type:', type(raw).__name__)
            if isinstance(raw, str):
                try:
                    contents = base64.b64decode(raw, validate=True)
                    path = output / (doc['name'].split('/')[-1] + '.bin')
                    path.write_bytes(contents)
                    with Image.open(io.BytesIO(contents)) as image:
                        print('Image format and dimensions:', image.format, image.size)
                        image.verify()
                    print('Byte count:', len(contents), 'signature:', contents[:16].hex(), 'saved:', path.name)
                    if '--repair-missing-kind' in sys.argv and 'kind' not in data:
                        backup = output / (doc['name'].split('/')[-1] + '.json')
                        if not backup.exists():
                            backup.write_text(json.dumps(doc), encoding='utf-8')
                        data['kind'] = 'photo'
                        endpoint = 'https://firestore.googleapis.com/v1/' + doc['name']
                        repaired = 'NEURAL_FILE:' + json.dumps(data, ensure_ascii=False, separators=(',', ':'))
                        response = s.patch(endpoint, params={'updateMask.fieldPaths': 'text', 'currentDocument.updateTime': doc['updateTime']}, json={'fields': {'text': {'stringValue': repaired}}}, timeout=30)
                        response.raise_for_status()
                        check = s.get(endpoint, timeout=30)
                        check.raise_for_status()
                        assert check.json()['fields']['text']['stringValue'] == repaired
                        print('Missing image type repaired and verified; image bytes unchanged.')
                except Exception as error:
                    raise RuntimeError('Requested attachment inspection/repair failed: ' + type(error).__name__) from None
        else:
            media_id = data.get('id', '')
            r = s.get(base + '/chatMedia/' + media_id, timeout=30)
            print('Media metadata status:', r.status_code)
            if r.status_code == 200:
                fields = r.json().get('fields', {})
                print('Metadata kind/size/ready:', {key: fields.get(key) for key in ['kind', 'size', 'ready', 'createdAt']})
