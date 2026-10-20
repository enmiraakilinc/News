"""Read authoritative aggregate Firestore storage; never download user media."""
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from google_owner_session import owner_session
from firebase_config import PROJECT_ID

session = owner_session()
now = datetime.now(timezone.utc)
r = session.get(f'https://monitoring.googleapis.com/v3/projects/{PROJECT_ID}/timeSeries', params={
    'filter': 'metric.type="firestore.googleapis.com/storage/data_and_index_storage_bytes"',
    'interval.startTime': (now - timedelta(days=7)).isoformat(),
    'interval.endTime': now.isoformat(), 'pageSize': 1,
}, timeout=30)
report = {'checkedAt': now.isoformat(), 'status': r.status_code}
if r.ok:
    series = r.json().get('timeSeries', [])
    values = []
    for item in series:
        if item.get('resource', {}).get('labels', {}).get('database_id', '(default)') != '(default)': continue
        points = item.get('points', [])
        if points:
            values.append(int(points[0]['value'].get('int64Value', 0)))
            report['observedAt'] = points[0].get('interval', {}).get('endTime')
    if values:
        report.update(bytes=sum(values), freeLimitBytes=1024**3, percent=round(sum(values)/1024**3*100, 2))
    else: report['metricUnavailable'] = True
else:
    error = r.json().get('error', {})
    report['errorStatus'] = error.get('status')
    report['reasons'] = [d.get('reason') for d in error.get('details', []) if d.get('reason')]
Path('private/backups/server-storage-metric-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report))
