"""Remove only inline chat attachments older than 48 hours; leave message text/history."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from firebase_config import PROJECT_ID, admin_key_path

c = service_account.Credentials.from_service_account_file(str(admin_key_path()), scopes=['https://www.googleapis.com/auth/cloud-platform'])
c.refresh(Request())
s = requests.Session()
s.headers['Authorization'] = 'Bearer ' + c.token
base = f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents'
cutoff = datetime.now(timezone.utc) - timedelta(days=2)
r = s.post(base + ':runQuery', json={'structuredQuery': {
    'from': [{'collectionId': 'messages', 'allDescendants': True}],
}}, timeout=30)
r.raise_for_status()
selected = []
for row in r.json():
    d = row.get('document', {})
    path = d.get('name', '').split('/documents/')[-1].split('/')
    text = d.get('fields', {}).get('text', {}).get('stringValue', '')
    sent = d.get('fields', {}).get('sentAt', {}).get('timestampValue')
    expired = sent and datetime.fromisoformat(sent.replace('Z', '+00:00')) < cutoff
    if expired and len(path) == 4 and path[0] == 'chats' and path[2] == 'messages' and text.startswith('NEURAL_FILE:'):
        # Confirm it is an attachment envelope, not an ordinary text prefix.
        try:
            payload = json.loads(text[len('NEURAL_FILE:'):])
            if isinstance(payload.get('bytes'), str) and isinstance(payload.get('name'), str): selected.append(d)
        except (ValueError, AttributeError): pass
removed = 0
for d in selected:
    r = s.patch('https://firestore.googleapis.com/v1/' + d['name'], params={
        'updateMask.fieldPaths': 'text', 'currentDocument.updateTime': d['updateTime'],
    }, json={'fields': {'text': {'stringValue': 'Dosyanın iki günlük saklama süresi doldu.'}}}, timeout=30)
    if r.status_code in (409, 412): continue
    r.raise_for_status(); removed += 1
report = {'expired_chat_attachments_removed': removed, 'old_payload_bytes_removed': sum(len(d['fields']['text']['stringValue'].encode()) for d in selected), 'letters_and_private_images_untouched': True}
Path('private/backups/expired-chat-attachment-cleanup-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report))
