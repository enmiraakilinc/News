"""Prepare a read-only legacy rule set. Apply only during an approved cutover.

API schema: https://firebase.google.com/docs/reference/rules/rest/v1/projects.releases/patch
"""
import argparse,json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.admin.firebase_config import PROJECT_ID,admin_session

def read_only_rules(source):
    def replace(match):
        actions=[v.strip() for v in match.group(1).split(',')]
        if any(v not in ['get','list','read','create','update','delete','write'] for v in actions):
            raise ValueError('Unknown rule action; manual review required')
        reads=[v for v in actions if v in ['get','list','read']]
        return 'allow '+', '.join(reads)+': if '+match.group(2)+';' if reads else '// Writes moved to the authenticated VPS.'
    result=re.sub(r'allow\s+([^:]+):\s*if\s*(.*?);',replace,source,flags=re.S)
    for actions in re.findall(r'allow\s+([^:]+):',result):
        if any(v.strip() not in ['get','list','read'] for v in actions.split(',')):
            raise ValueError('A legacy write permission survived')
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    session=admin_session();base='https://firebaserules.googleapis.com/v1/'
    name=f'projects/{PROJECT_ID}/releases/cloud.firestore'
    response=session.get(base+name,timeout=30);response.raise_for_status();release=response.json()
    response=session.get(base+release['rulesetName'],timeout=30);response.raise_for_status();rules=response.json()
    files=rules['source']['files']
    if len(files)!=1:raise ValueError('Multiple rule files require manual review')
    original=files[0]['content'];prepared=read_only_rules(original)
    destination=ROOT/'private/primary-cutover';destination.mkdir(parents=True,exist_ok=True)
    backup=destination/'firebase-rules-before.json'
    if not backup.exists():backup.write_text(json.dumps({'release':release,'rules':rules},indent=2),encoding='utf-8')
    (destination/'firestore-readonly.rules').write_text(prepared,encoding='utf-8')
    report={'prepared':True,'legacyReadRulesPreserved':True,'legacyWritesAllowed':False,'applied':False}
    if args.apply:
        # Preserve the exact deployed read rules; never replace them with a
        # permissive global rule. Firebase user data is not deleted.
        response=session.post(base+f'projects/{PROJECT_ID}/rulesets',json={'source':{'files':[{'name':files[0]['name'],'content':prepared}]}},timeout=30)
        response.raise_for_status();new_rules=response.json()['name']
        response=session.patch(base+name,json={'release':{'name':name,'rulesetName':new_rules},'updateMask':'rulesetName'},timeout=30)
        response.raise_for_status()
        if response.json()['rulesetName']!=new_rules:raise RuntimeError('Rule activation verification failed')
        report['applied']=True
    print(json.dumps(report))

if __name__=='__main__':main()
