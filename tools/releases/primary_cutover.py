"""Explicitly approved 1.16.0 publication and guarded primary cutover.

Run prepare before freezing legacy writes; activate compares every source
document version before stopping replication. Never rolls primary writes back.
The legacy metadata repository alias stays pinned for old Worker clients.
"""
import argparse, hashlib, json, re, subprocess, sys, time
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.admin.firebase_config import PROJECT_ID, admin_session
from tools.server.ssh_admin import SSH, KEY, HOST

GH = 'C:/Program Files/GitHub CLI/gh.exe'
REPO_ID = 1426918054
REPO = 'enmiraakilinc/News'
VERSION = '1.16.0'
DIRECTORY = ROOT / 'artifacts/releases' / VERSION
PRIVATE = ROOT / 'private/primary-cutover'

def gh(*args):
    return subprocess.check_output([GH, *args], text=True, encoding='utf-8').strip()

def remote(script):
    result = subprocess.run([SSH, '-i', str(KEY), '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=15', HOST, 'python3 -'], input=script,
        text=True, encoding='utf-8', capture_output=True, timeout=180, check=True)
    return result.stdout.strip()

def sql(query):
    return remote('import subprocess\nprint(subprocess.check_output('+repr([
        'sudo','-n','-u','postgres','psql','-XAt','-v','ON_ERROR_STOP=1',
        '-d','neural_haber','-c',query])+',text=True))\n')

def report():
    data=json.loads((DIRECTORY/'build-report.json').read_text(encoding='utf-8-sig'))
    apk=DIRECTORY/data['filename']
    assert data['version']==VERSION and data['code']==2081
    assert data['postgresPrimary'] and data['signingVerified'] and not data['debuggable']
    assert data['abi']==['arm64-v8a']
    assert apk.stat().st_size==data['bytes']
    assert hashlib.sha256(apk.read_bytes()).hexdigest()==data['sha256']
    return data,apk

def prepare():
    data,apk=report()
    repository=json.loads(gh('api',f'repositories/{REPO_ID}'))
    assert repository['private'] and repository['full_name']==REPO
    releases=json.loads(gh('api',f'repositories/{REPO_ID}/releases?per_page=100'))
    release=next((r for r in releases if r['tag_name']=='v'+VERSION),None)
    if release is None:
        gh('release','create','v'+VERSION,str(apk),'--repo',REPO,'--draft',
            '--title',VERSION,'--notes','Maintenance update.',
            '--target',gh('api',f'repositories/{REPO_ID}/commits/main','--jq','.sha'))
        releases=json.loads(gh('api',f'repositories/{REPO_ID}/releases?per_page=100'))
        release=next(r for r in releases if r['tag_name']=='v'+VERSION)
    asset=next(a for a in release['assets'] if a['name']==apk.name)
    assert asset['size']==data['bytes'] and asset.get('digest')=='sha256:'+data['sha256']
    # The private GitHub token is sent only to api.github.com, never to the CDN.
    response=requests.get(f'https://api.github.com/repositories/{REPO_ID}/releases/assets/{asset["id"]}',
        headers={'Authorization':'Bearer '+gh('auth','token'),'Accept':'application/octet-stream'},
        allow_redirects=False,stream=True,timeout=60)
    if response.status_code==302:
        from urllib.parse import urlparse
        location=response.headers['Location'];parsed=urlparse(location)
        assert parsed.scheme=='https' and parsed.hostname in ['release-assets.githubusercontent.com','objects.githubusercontent.com']
        response.close();response=requests.get(location,stream=True,timeout=90)
    response.raise_for_status()
    digest=hashlib.sha256();size=0
    with response:
        for block in response.iter_content(1024*1024):digest.update(block);size+=len(block)
    assert size==data['bytes'] and digest.hexdigest()==data['sha256']
    if release['draft']:gh('release','edit','v'+VERSION,'--repo',REPO,'--draft=false','--latest')
    subprocess.run([sys.executable,str(ROOT/'tools/releases/prepare_private_updates.py'),
        '--version',VERSION,'--apply'],check=True)
    PRIVATE.mkdir(parents=True,exist_ok=True)
    (PRIVATE/'release.json').write_text(json.dumps({'repository':REPO,'repositoryId':REPO_ID,
        'assetId':asset['id'],'sha256':data['sha256'],'githubDownloadVerified':True},indent=2))
    print(json.dumps({'privateReleasePublished':True,'version':VERSION,'legacyMetadataUpdated':True}))

def timestamp(value):
    match=re.fullmatch(r'(.*?)(?:\.(\d+))?Z',value)
    if not match:raise ValueError('Unexpected source timestamp')
    return match[1]+'.'+(match[2] or '').ljust(9,'0')+'Z'

def destination():
    rows=json.loads(sql("SELECT coalesce(json_agg(json_build_array(path,document->>'updateTime')),'[]') FROM neural.documents WHERE origin='firebase'"))
    return {path:timestamp(stamp) for path,stamp in rows}

def activate():
    data,_=report()
    assert (PRIVATE/'release.json').exists()
    assert sql("SELECT value FROM neural.settings WHERE key='primary_writes'")=='false', 'Already primary; never repeat source reconciliation'
    session=admin_session()
    response=session.get(f'https://firebaserules.googleapis.com/v1/projects/{PROJECT_ID}/releases/cloud.firestore',timeout=30)
    response.raise_for_status()
    rules=session.get('https://firebaserules.googleapis.com/v1/'+response.json()['rulesetName'],timeout=30)
    rules.raise_for_status()
    for file in rules.json()['source']['files']:
        for actions in re.findall(r'allow\s+([^:]+):',file['content']):
            assert all(a.strip() in ['get','list','read'] for a in actions.split(',')), 'Legacy writes must be frozen first'
    groups=json.loads(sql("SELECT json_agg(collection_id) FROM neural.sync_state WHERE collection_id NOT LIKE '\\_\\_%'"))
    assert len(groups)>=30
    source={}
    base=f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents'
    for group in groups:
        response=session.post(base+':runQuery',json={'structuredQuery':{
            'select':{'fields':[{'fieldPath':'__name__'}]},
            'from':[{'collectionId':group,'allDescendants':True}]}},timeout=90)
        response.raise_for_status()
        for item in response.json():
            if 'document' in item:
                doc=item['document'];source[doc['name'].split('/documents/',1)[1]]=timestamp(doc['updateTime'])
    # A short bounded wait allows the already running mirror to finish its queue.
    for attempt in range(6):
        target=destination()
        if target==source:break
        if attempt==5:
            (PRIVATE/'version-mismatch.json').write_text(json.dumps({'sourceOnly':sorted(source.keys()-target.keys()),
                'targetOnly':sorted(target.keys()-source.keys()),
                'differentVersions':[p for p in source.keys()&target.keys() if source[p]!=target[p]]}))
            raise RuntimeError('Final source comparison differs; primary remains disabled')
        time.sleep(5)
    print(json.dumps({'finalDocumentVersionsMatched':len(source)}),flush=True)
    remote("import subprocess\nsubprocess.run(['sudo','systemctl','disable','--now','neural-sync'],check=True)\n")
    assert destination()==source, 'Mirror changed during stop; primary remains disabled'
    sql("BEGIN; UPDATE neural.settings SET value='true' WHERE key='primary_writes'; COMMIT;")
    result=requests.get('https://138.2.185.151/v1/capabilities',timeout=20)
    result.raise_for_status();assert result.json()['primaryWrites'] is True
    current=json.loads(sql("SELECT document->'fields' FROM neural.documents WHERE path='config/private_app_version'"))
    assert current['name']['stringValue']==VERSION and current['sha256']['stringValue']==data['sha256']
    (PRIVATE/'activation.json').write_text(json.dumps({'matchedDocumentVersions':len(source),
        'primaryEnabled':True,'mirrorStopped':True,'activatedAt':time.time()},indent=2))
    data.update(published=True,livePrimaryEnabled=True,privateDownloadVerified=True,
        appVersionVerified=True,releaseUrl=f'https://github.com/{REPO}/releases/tag/v{VERSION}')
    (DIRECTORY/'build-report.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'primaryEnabled':True,'mirrorStopped':True,'version':VERSION}))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('phase',choices=['prepare','activate'])
    args=parser.parse_args()
    {'prepare':prepare,'activate':activate}[args.phase]()
