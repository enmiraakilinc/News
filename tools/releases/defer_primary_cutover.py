"""Restore compatibility only if primary has never accepted writes.

Used when final source verification is blocked by the free Firestore quota.
Never use after the primary mode was enabled.
"""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.releases.primary_cutover import sql,remote,gh,REPO,PRIVATE,DIRECTORY
from tools.admin.firebase_config import admin_session,PROJECT_ID

def main():
    assert sql("SELECT value FROM neural.settings WHERE key='primary_writes'")=='false'
    assert sql("SELECT count(*) FROM neural.documents WHERE origin='postgres'")=='0'
    session=admin_session()
    previous=json.loads((ROOT/'private/backups/private-updates-before-1.16.0.json').read_text())['config/private_app_version']
    assert previous['fields']['name']['stringValue']=='1.15.1'
    backup=json.loads((PRIVATE/'firebase-rules-before.json').read_text())
    name=f'projects/{PROJECT_ID}/releases/cloud.firestore'
    original=backup['release']['rulesetName']
    response=session.patch('https://firebaserules.googleapis.com/v1/'+name,
        json={'release':{'name':name,'rulesetName':original},'updateMask':'rulesetName'},timeout=30)
    response.raise_for_status();assert response.json()['rulesetName']==original
    endpoint=f'https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/config/private_app_version'
    # Avoid another charged source read when the daily read quota is exhausted.
    # The running mirror preserves the authoritative updateTime for a guarded
    # metadata restoration; a concurrent change causes a failed precondition.
    current=json.loads(sql("SELECT document FROM neural.documents WHERE path='config/private_app_version'"))
    assert current['fields']['name']['stringValue'] in ['1.15.1','1.16.0']
    response=session.patch(endpoint,params=[('updateMask.fieldPaths',k) for k in previous['fields']]+
        [('currentDocument.updateTime',current['updateTime'])],json={'fields':previous['fields']},timeout=30)
    response.raise_for_status()
    gh('release','edit','v1.16.0','--repo',REPO,'--draft=true')
    gh('release','edit','v1.15.1','--repo',REPO,'--latest')
    assert remote("import subprocess\nprint(subprocess.check_output(['sudo','systemctl','is-active','neural-sync'],text=True))\n")=='active'
    report=json.loads((DIRECTORY/'build-report.json').read_text(encoding='utf-8-sig'))
    report.update(published=False,livePrimaryEnabled=False,deferredReason='Firestore free daily read quota blocked final version comparison',
        compatibilityRestored=True,githubDraftReady=True,githubDownloadVerified=True)
    (DIRECTORY/'build-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    (PRIVATE/'deferred.json').write_text(json.dumps({'primaryEnabled':False,'legacyRulesRestored':True,
        'latestVersionRestored':'1.15.1','draftVersion':'1.16.0','reason':'source-read-quota'},indent=2))
    print(json.dumps({'primaryEnabled':False,'legacyRulesRestored':True,'latestVersionRestored':'1.15.1','draftVersion':'1.16.0'}))

if __name__=='__main__':main()
