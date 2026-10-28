"""Publish a release APK after primary cutover; never change migration state."""
import argparse,hashlib,json,re,subprocess,sys,time
from pathlib import Path
from urllib.parse import urlparse
import requests
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.releases.primary_cutover import gh,sql,remote,REPO_ID
from tools.releases.repository import RELEASE_REPOSITORY as LEGACY_ALIAS
from tools.admin.firebase_config import admin_session,PROJECT_ID

def quote(value):return "'"+value.replace("'","''")+"'"

def publish(version):
    assert re.fullmatch(r'\d+\.\d+\.\d+',version)
    directory=ROOT/'artifacts/releases'/version
    report=json.loads((directory/'build-report.json').read_text(encoding='utf-8-sig'))
    apk=directory/report['filename']
    assert apk.resolve().parent==directory.resolve()
    assert report['version']==version and report['postgresPrimary'] and report['signingVerified']
    assert report['abi']==['arm64-v8a'] and not report['debuggable']
    assert hashlib.sha256(apk.read_bytes()).hexdigest()==report['sha256'] and apk.stat().st_size==report['bytes']
    assert sql("SELECT value FROM neural.settings WHERE key='primary_writes'")=='true'
    health=requests.get('https://138.2.185.151/health',timeout=20);health.raise_for_status()
    assert health.json()['mode']=='primary'
    before=json.loads(sql("SELECT document FROM neural.documents WHERE path='config/private_app_version'"))
    assert int(before['fields']['code']['integerValue'])<=report['code']
    staged=remote("import subprocess\nprint(subprocess.check_output(['sudo','sha256sum',"+repr('/var/lib/neural/releases/'+version+'.apk')+"],text=True).split()[0])\n")
    assert staged==report['sha256'],'Stage the immutable private VPS APK first'
    repository=json.loads(gh('api',f'repositories/{REPO_ID}'))
    assert repository['id']==REPO_ID and repository['full_name']==LEGACY_ALIAS
    repo=repository['full_name']
    head=subprocess.check_output(['git','-c','safe.directory='+ROOT.as_posix(),'rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    assert gh('api',f'repositories/{REPO_ID}/commits/main','--jq','.sha')==head,'Push reviewed source before release'
    releases=json.loads(gh('api',f'repositories/{REPO_ID}/releases?per_page=100'))
    release=next((r for r in releases if r['tag_name']=='v'+version),None)
    if release is None:
        gh('release','create','v'+version,str(apk),'--repo',repo,'--draft','--target',head,'--title',version,'--notes','Maintenance update.')
        release=next(r for r in json.loads(gh('api',f'repositories/{REPO_ID}/releases?per_page=100')) if r['tag_name']=='v'+version)
    asset=next(a for a in release['assets'] if a['name']==apk.name)
    assert asset['size']==report['bytes'] and asset.get('digest')=='sha256:'+report['sha256']
    response=requests.get(f'https://api.github.com/repositories/{REPO_ID}/releases/assets/{asset["id"]}',
        headers={'Authorization':'Bearer '+gh('auth','token'),'Accept':'application/octet-stream'},
        allow_redirects=False,stream=True,timeout=30)
    if response.status_code==302:
        location=response.headers['Location'];parsed=urlparse(location)
        assert parsed.scheme=='https' and parsed.hostname in ['release-assets.githubusercontent.com','objects.githubusercontent.com']
        response.close()
        # Send only the short-lived, single-asset URL to the VPS, never the PAT.
        proof=json.loads(remote("import urllib.request,hashlib,json\nh=hashlib.sha256();size=0\nwith urllib.request.urlopen("+repr(location)+",timeout=60) as r:\n while True:\n  block=r.read(1048576)\n  if not block:break\n  h.update(block);size+=len(block)\nprint(json.dumps({'sha256':h.hexdigest(),'bytes':size}))\n"))
    else:
        response.raise_for_status();digest=hashlib.sha256();size=0
        with response:
            for block in response.iter_content(1048576):digest.update(block);size+=len(block)
        proof={'sha256':digest.hexdigest(),'bytes':size}
    assert proof['sha256']==report['sha256'] and proof['bytes']==report['bytes']
    print('GitHub release and staged VPS APK hashes verified.',flush=True)
    fields={'code':{'integerValue':str(report['code'])},'name':{'stringValue':version},
        'notes':{'stringValue':'Genel görünüm ve kararlılık iyileştirmeleri.'},
        'repository':{'stringValue':LEGACY_ALIAS},'assetId':{'integerValue':str(asset['id'])},'sha256':{'stringValue':report['sha256']}}
    session=admin_session()
    base=f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents'
    endpoint=base+'/config/private_app_version'
    old=session.get(endpoint,timeout=30);old.raise_for_status();previous=old.json()
    assert int(previous['fields']['code']['integerValue'])<=report['code']
    backup=ROOT/'private/backups'/('primary-release-before-'+version+'.json')
    backup.parent.mkdir(parents=True,exist_ok=True)
    if not backup.exists():backup.write_text(json.dumps({'postgres':before,'legacy':previous},indent=2),encoding='utf-8')
    # Preserve explicit administrator denials; grant newly added chat members.
    members=json.loads(sql("SELECT coalesce(json_agg(DISTINCT member->>'stringValue'),'[]') FROM neural.documents d CROSS JOIN LATERAL jsonb_array_elements(coalesce(d.document#>'{fields,members,arrayValue,values}','[]')) member WHERE d.collection_id IN ('chats','couples')"))
    access=json.loads(sql("SELECT coalesce(json_object_agg(document_id,document#>'{fields,enabled,booleanValue}'),'{}') FROM neural.documents WHERE collection_id='updateAccess'"))
    for uid in members:
        assert re.fullmatch(r'[A-Za-z0-9_-]{1,128}',uid)
        access.setdefault(uid,True)
        access[uid] = access[uid] is True
        r=session.patch(base+'/updateAccess/'+uid,params={'updateMask.fieldPaths':'enabled'},json={'fields':{'enabled':{'booleanValue':access[uid]}}},timeout=30)
        r.raise_for_status()
    if release['draft']:gh('release','edit','v'+version,'--repo',repo,'--draft=false','--latest')
    r=session.patch(endpoint,params=[('updateMask.fieldPaths',k) for k in fields]+[('currentDocument.updateTime',previous['updateTime'])],json={'fields':fields},timeout=30)
    r.raise_for_status()
    document=r.json()
    statements=["DO $$ BEGIN IF EXISTS(SELECT 1 FROM neural.documents WHERE path='config/private_app_version' AND (document#>>'{fields,code,integerValue}')::int>"+str(report['code'])+") THEN RAISE EXCEPTION 'Newer release exists'; END IF; END $$;",
        "UPDATE neural.documents SET document="+quote(json.dumps(document))+"::jsonb,origin='postgres',revision=DEFAULT,changed_at=now() WHERE path='config/private_app_version';"]
    for uid in members:
        path='updateAccess/'+uid;doc=json.dumps({'fields':{'enabled':{'booleanValue':access[uid]}}})
        statements.append("INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document,origin) VALUES ("+','.join(quote(v) for v in [path,'updateAccess','updateAccess',uid,doc])+"::jsonb,'postgres') ON CONFLICT(path) DO UPDATE SET document=EXCLUDED.document,origin='postgres',revision=DEFAULT,changed_at=now();")
    sql('BEGIN;'+''.join(statements)+'COMMIT;')
    report.update(published=True,livePrimaryEnabled=True,primaryCutoverRequired=False,sourceCommit=head,
        githubDownloadVerified=True,releaseUrl=f'https://github.com/{repo}/releases/tag/v{version}',
        legacyMetadataUpdated=True,vpsMetadataUpdated=True,physicalDeviceTested=False)
    (directory/'build-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'published':version,'code':report['code'],'eligibleMembers':len(members),'primaryStateUnchanged':True,'repositoryPrivate':repository['private']}))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--version',required=True)
    publish(parser.parse_args().version)
