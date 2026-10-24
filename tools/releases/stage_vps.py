"""Copy a verified APK privately to the VPS without publishing version metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import uuid

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute,KEY,HOST

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--version',required=True)
    args=parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+',args.version):raise ValueError('Invalid version')
    directory=ROOT/'artifacts/releases'/args.version
    report=json.loads((directory/'build-report.json').read_text(encoding='utf-8-sig'))
    if not report['signingVerified'] or report['debuggable'] or report['version']!=args.version:raise ValueError('Unverified APK')
    apk=directory/report['filename']
    if apk.resolve().parent!=directory.resolve():raise ValueError('Invalid artifact path')
    digest=hashlib.sha256(apk.read_bytes()).hexdigest()
    if digest!=report['sha256']:raise ValueError('APK hash mismatch')
    nonce=uuid.uuid4().hex
    temporary='/var/tmp/neural-stage-'+nonce
    execute("import pathlib\np=pathlib.Path("+repr(temporary)+")\nassert p.parent==pathlib.Path('/var/tmp') and p.name.startswith('neural-stage-')\np.mkdir(mode=0o700)\n")
    try:
        subprocess.run(['C:/Windows/System32/OpenSSH/scp.exe','-q','-i',str(KEY),'-o','BatchMode=yes',str(apk),HOST+':'+temporary+'/release.apk'],check=True)
        script='''import pathlib,hashlib,subprocess,json
def stage(options):
    source=pathlib.Path(options['temporary'])/'release.apk'
    assert source.resolve().parent.parent==pathlib.Path('/var/tmp')
    assert source.parent.name.startswith('neural-stage-')
    if hashlib.sha256(source.read_bytes()).hexdigest()!=options['sha256']:raise RuntimeError('Transfer hash mismatch')
    target='/var/lib/neural/releases/'+options['version']+'.apk'
    subprocess.run(['sudo','-n','install','-d','-m','750','-o','root','-g','neural_api','/var/lib/neural/releases'],check=True)
    exists=subprocess.run(['sudo','-n','test','-f',target]).returncode==0
    if exists:
        actual=subprocess.check_output(['sudo','-n','sha256sum',target],text=True).split()[0]
        if actual!=options['sha256']:raise RuntimeError('Refusing to replace an immutable APK version')
    else:subprocess.run(['sudo','-n','install','-m','640','-o','root','-g','neural_api',str(source),target],check=True)
    print(json.dumps({'stagedVersion':options['version'],'bytes':source.stat().st_size,'transferHashVerified':True,'updateMetadataChanged':False,'published':False}))
'''
        execute(script+'\nstage('+repr({'temporary':temporary,'version':args.version,'sha256':digest})+')\n')
    finally:
        execute("import pathlib\np=pathlib.Path("+repr(temporary)+")\nassert p.resolve().parent==pathlib.Path('/var/tmp') and p.name.startswith('neural-stage-')\n(p/'release.apk').unlink(missing_ok=True)\np.rmdir()\n")
    report['stagedOnVps']=True
    (directory/'build-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
