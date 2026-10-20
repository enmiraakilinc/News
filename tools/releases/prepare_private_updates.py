"""Stage private update metadata and explicitly grant existing chat members.

Does not upload APKs, change repository visibility, or remove the legacy route.
Run without --apply for a read-only review. No credentials are printed.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.admin.firebase_config import PROJECT_ID, admin_key_path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--metadata-only', action='store_true', help='Update release metadata without changing access grants.')
    args = parser.parse_args()
    import re
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        raise ValueError('Invalid version')
    report = json.loads((ROOT/'artifacts/releases'/args.version/'build-report.json').read_text(encoding='utf-8-sig'))
    if not report['signingVerified'] or report['version'] != args.version:
        raise ValueError('Unverified build')
    gh = 'C:/Program Files/GitHub CLI/gh.exe'
    release = json.loads(subprocess.check_output([gh,'api',f'repos/kunduracimelek/NeuralScope/releases/tags/v{args.version}'], encoding='utf-8'))
    asset = next(a for a in release['assets'] if a['name'] == report['filename'])
    if asset.get('digest') != 'sha256:'+report['sha256'] or asset['size'] != report['bytes']:
        raise ValueError('Release does not match build')
    session = AuthorizedSession(service_account.Credentials.from_service_account_file(str(admin_key_path()), scopes=['https://www.googleapis.com/auth/cloud-platform']))
    base = f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents'
    members = set()
    for collection in ([] if args.metadata_only else ['couples','chats']):
        page = None
        while True:
            params = {'pageSize':100,'mask.fieldPaths':'members'}
            if page: params['pageToken'] = page
            response = session.get(f'{base}/{collection}',params=params,timeout=30)
            response.raise_for_status()
            data = response.json()
            for doc in data.get('documents',[]):
                members.update(v['stringValue'] for v in doc.get('fields',{}).get('members',{}).get('arrayValue',{}).get('values',[]) if 'stringValue' in v)
            page = data.get('nextPageToken')
            if not page: break
    print(f'Validated release {args.version}; {"metadata only, access grants unchanged" if args.metadata_only else str(len(members))+" existing conversation members eligible"}. Repository visibility unchanged.')
    if not args.apply: return
    updates = {'config/private_app_version':{'code':{'integerValue':str(report['code'])},'name':{'stringValue':args.version},'notes':{'stringValue':'Genel iyileştirmeler.'},'assetId':{'integerValue':str(asset['id'])},'sha256':{'stringValue':report['sha256']}}}
    for uid in members:
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}',uid): raise ValueError('Invalid account ID')
        updates[f'updateAccess/{uid}'] = {'enabled':{'booleanValue':True}}
    backup = ROOT/'private/backups'/f'private-updates-before-{args.version}.json'
    backup.parent.mkdir(parents=True,exist_ok=True)
    previous = {}
    for key in updates:
        r = session.get(f'{base}/{key}',timeout=30)
        if r.status_code != 404: r.raise_for_status()
        previous[key] = None if r.status_code == 404 else r.json()
        if key == 'config/private_app_version' and previous[key] and int(previous[key]['fields']['code']['integerValue']) > report['code']:
            raise ValueError('Newer private release already configured; no changes applied')
    if not backup.exists(): backup.write_text(json.dumps(previous,indent=2),encoding='utf-8')
    for key,fields in updates.items():
        old = previous[key]
        params = [('updateMask.fieldPaths',k) for k in fields]
        params += [('currentDocument.updateTime',old['updateTime'])] if old else [('currentDocument.exists','false')]
        r = session.patch(f'{base}/{key}',params=params,json={'fields':fields},timeout=30)
        r.raise_for_status()
    print('Private metadata staged; existing access grants unchanged.' if args.metadata_only else 'Private metadata and access grants staged.')
    print('No public metadata or repository visibility changed.')

if __name__ == '__main__': main()
