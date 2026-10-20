"""Report storage without exposing content. --cleanup removes expired chat invites only."""
import argparse
import base64
from collections import defaultdict
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from firebase_config import PROJECT_ID, admin_key_path

parser = argparse.ArgumentParser()
parser.add_argument('--cleanup', action='store_true')
args = parser.parse_args()
credentials = service_account.Credentials.from_service_account_file(str(admin_key_path()),
    scopes=['https://www.googleapis.com/auth/cloud-platform'])
credentials.refresh(Request())
session = requests.Session()
session.headers['Authorization'] = 'Bearer ' + credentials.token
base = f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents'
now = datetime.now(timezone.utc)
stats = defaultdict(lambda: {'documents': 0, 'estimated_document_bytes': 0})
candidates = []
visited = 0

def string_size(value):
    return len(value.encode('utf-8')) + 1

def value_size(value):
    if 'stringValue' in value:
        return string_size(value['stringValue'])
    if 'bytesValue' in value:
        return len(base64.b64decode(value['bytesValue']))
    if 'mapValue' in value:
        return 32 + fields_size(value['mapValue'].get('fields', {}))
    if 'arrayValue' in value:
        return sum(value_size(v) for v in value['arrayValue'].get('values', []))
    if 'referenceValue' in value:
        return 16 + sum(string_size(s) for s in value['referenceValue'].split('/documents/')[-1].split('/'))
    if 'geoPointValue' in value:
        return 16
    if 'booleanValue' in value or 'nullValue' in value:
        return 1
    return 8

def fields_size(fields):
    return sum(string_size(key) + value_size(value) for key, value in fields.items())

def collection_ids(parent):
    token = None
    while True:
        body = {'pageSize': 1000}
        if token:
            body['pageToken'] = token
        response = session.post(parent + ':listCollectionIds', json=body, timeout=30)
        response.raise_for_status()
        result = response.json()
        yield from result.get('collectionIds', [])
        token = result.get('nextPageToken')
        if not token:
            return

def walk(parent):
    global visited
    for collection in collection_ids(parent):
        token = None
        while True:
            params = {'pageSize': 100, 'showMissing': 'true'}
            if token:
                params['pageToken'] = token
            response = session.get(parent + '/' + collection, params=params, timeout=30)
            response.raise_for_status()
            result = response.json()
            for document in result.get('documents', []):
                visited += 1
                if visited > 5000:
                    raise RuntimeError('Audit stopped at 5000 documents; no cleanup performed.')
                name = document['name']
                if 'updateTime' in document:
                    group = stats[collection]
                    group['documents'] += 1
                    group['estimated_document_bytes'] += 32 + 16 + sum(
                        string_size(s) for s in name.split('/documents/')[1].split('/')) + fields_size(document.get('fields', {}))
                    if collection == 'chatInvites' and parent == base:
                        expiry = document.get('fields', {}).get('expiresAt', {}).get('timestampValue')
                        if expiry and datetime.fromisoformat(expiry.replace('Z', '+00:00')) < now - timedelta(days=1):
                            candidates.append(document)
                walk('https://firestore.googleapis.com/v1/' + name)
            token = result.get('nextPageToken')
            if not token:
                break

walk(base)
report = {'checked_at_utc': now.isoformat(), 'collections': dict(stats),
    'estimated_document_bytes': sum(v['estimated_document_bytes'] for v in stats.values()),
    'estimate_excludes_indexes_backups_and_other_services': True,
    'expired_chat_invites_older_than_one_day': len(candidates), 'deleted_chat_invites': 0}

# The authoritative metric includes index storage; permissions may differ.
start = (now - timedelta(days=7)).isoformat()
metric = session.get(f'https://monitoring.googleapis.com/v3/projects/{PROJECT_ID}/timeSeries',
    params={'filter': 'metric.type="firestore.googleapis.com/storage/data_and_index_storage_bytes"',
        'interval.startTime': start, 'interval.endTime': now.isoformat(), 'pageSize': 100}, timeout=30)
if metric.ok:
    series = metric.json().get('timeSeries', [])
    report['monitoring_storage_series'] = [
        {'labels': item.get('metric', {}).get('labels', {}), 'latest': item.get('points', [])[:1]}
        for item in series]
else:
    report['monitoring_storage_status'] = metric.status_code

if args.cleanup and candidates:
    backup = Path('expired-chat-invites-backup.json')
    if backup.exists():
        raise RuntimeError('Cleanup backup already exists; stopped to preserve it.')
    backup.write_text(json.dumps(candidates, ensure_ascii=False, indent=2), encoding='utf-8')
    for document in candidates:
        response = session.delete('https://firestore.googleapis.com/v1/' + document['name'],
            params={'currentDocument.updateTime': document['updateTime']}, timeout=30)
        if response.status_code in (404, 409, 412):
            continue
        response.raise_for_status()
        report['deleted_chat_invites'] += 1
Path('private/backups/server-storage-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
