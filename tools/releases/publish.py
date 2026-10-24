"""Publish an already reviewed release; never build or modify security rules."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import requests
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.admin.firebase_config import PROJECT_ID,admin_session
GH='C:/Program Files/GitHub CLI/gh.exe'
from tools.releases.repository import RELEASE_REPOSITORY as REPO

def gh(*args):
    return subprocess.check_output([GH,*args],text=True,encoding='utf-8').strip()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--version',required=True)
    parser.add_argument('--publish',action='store_true',required=True)
    parser.add_argument('--private',action='store_true',default=True,help='Publish only to a private repository and authenticated update service.')
    parser.add_argument('--notes-file',type=Path,default=ROOT/'docs/releases/NEXT_PUBLIC_NOTES.txt')
    args=parser.parse_args()
    notes=args.notes_file.read_text(encoding='utf-8-sig').strip() if args.notes_file.exists() else 'Görünüm ve kararlılık iyileştirmeleri.'
    if not notes or len(notes)>1000:raise ValueError('Public release notes must contain 1–1000 characters.')
    if not re.fullmatch(r'\d+\.\d+\.\d+',args.version):raise ValueError('Invalid version.')
    directory=ROOT/'artifacts/releases'/args.version
    report=json.loads((directory/'build-report.json').read_text(encoding='utf-8-sig'))
    if report.get('postgresPrimary'):
        raise RuntimeError('Primary releases require the reviewed VPS cutover procedure; do not publish via the Firebase compatibility publisher.')
    if report['version']!=args.version or not report['signingVerified']:raise RuntimeError('Build report mismatch.')
    if report['filename']!=f'Neural-Haber-{args.version}-arm64.apk' or report['abi']!=['arm64-v8a'] or report['debuggable']:raise RuntimeError('Unexpected release artifact.')
    apk=directory/report['filename']
    digest=hashlib.sha256(apk.read_bytes()).hexdigest()
    if apk.stat().st_size!=report['bytes'] or digest!=report['sha256']:raise RuntimeError('APK differs from reviewed report.')
    tag='v'+args.version
    if args.private and not json.loads(gh('api',f'repos/{REPO}'))['private']:
        raise RuntimeError('Private publishing requires a private source repository; no release was created.')
    releases=json.loads(gh('api',f'repos/{REPO}/releases?per_page=100'))
    release=next((r for r in releases if r['tag_name']==tag),None)
    if release is None:
        gh('release','create',tag,str(apk),'--repo',REPO,'--draft','--title',args.version,'--notes','Maintenance update.' if args.private else notes)
        releases=json.loads(gh('api',f'repos/{REPO}/releases?per_page=100'))
        release=next(r for r in releases if r['tag_name']==tag)
    asset=next(a for a in release['assets'] if a['name']==apk.name)
    if asset['size']!=report['bytes'] or asset.get('digest')!='sha256:'+digest:raise RuntimeError('Uploaded asset mismatch.')
    if release['draft']:gh('release','edit',tag,'--repo',REPO,'--draft=false','--latest')
    url=f'https://github.com/{REPO}/releases/download/{tag}/{apk.name}'
    remote=hashlib.sha256();size=0
    headers={}
    download=url
    if args.private:
        headers={'Authorization':'Bearer '+gh('auth','token'),'Accept':'application/octet-stream'}
        download=f'https://api.github.com/repos/{REPO}/releases/assets/{asset["id"]}'
    with requests.get(download,headers=headers,stream=True,timeout=60) as response:
        response.raise_for_status()
        for chunk in response.iter_content(1024*1024):remote.update(chunk);size+=len(chunk)
    if remote.hexdigest()!=digest or size!=report['bytes']:raise RuntimeError('Public download mismatch.')
    session=admin_session()
    config_name='private_app_version' if args.private else 'app_version'
    endpoint=f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/config/{config_name}'
    response=session.get(endpoint,timeout=30);response.raise_for_status();previous=response.json()
    if int(previous['fields']['code']['integerValue'])>report['code']:raise RuntimeError('Newer release already published.')
    backup=ROOT/'private/backups'/f'{config_name}-before-{args.version}.json'
    backup.parent.mkdir(parents=True,exist_ok=True)
    if not backup.exists():backup.write_text(json.dumps(previous,indent=2),encoding='utf-8')
    fields={'code':{'integerValue':str(report['code'])},'name':{'stringValue':args.version},'url':{'stringValue':url},'urlsByAbi':{'mapValue':{'fields':{'arm64-v8a':{'stringValue':url}}}},'notes':{'stringValue':notes}}
    if args.private:
        fields={'code':{'integerValue':str(report['code'])},'name':{'stringValue':args.version},'notes':{'stringValue':notes},'repository':{'stringValue':REPO},'assetId':{'integerValue':str(asset['id'])},'sha256':{'stringValue':digest}}
    response=session.patch(endpoint,params=[('updateMask.fieldPaths',key)for key in fields]+[('currentDocument.updateTime',previous['updateTime'])],json={'fields':fields},timeout=30);response.raise_for_status()
    config=json.loads((ROOT/'flutter_application_1/android/app/google-services.json').read_text(encoding='utf-8'))
    response=session.get(endpoint,timeout=30) if args.private else requests.get(endpoint,params={'key':config['client'][0]['api_key'][0]['current_key']},timeout=30)
    response.raise_for_status()
    if any(response.json()['fields'][key]!=value for key,value in fields.items()):raise RuntimeError('Update metadata verification failed.')
    report.update(published=True,publicDownloadVerified=not args.private,privateDownloadVerified=args.private,appVersionVerified=True,releaseUrl=f'https://github.com/{REPO}/releases/tag/{tag}')
    (directory/'build-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(f'{args.version} / {report["code"]} published; {"private" if args.private else "public"} APK and update metadata verified.')

if __name__=='__main__':main()
