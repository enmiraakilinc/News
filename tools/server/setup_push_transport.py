"""Connect the approved VPS to the existing Worker without moving Google keys."""
from pathlib import Path
import json
import secrets
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute

def main():
    path=ROOT/'private/server-push-transport.json'
    if path.exists():
        config=json.loads(path.read_text(encoding='utf-8'))
    else:
        config={'secret':secrets.token_hex(32),'url':'https://neural-wakeup.free-wakeup-worker.workers.dev/internal/push'}
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(config),encoding='utf-8')
    subprocess.run(['C:/Program Files/nodejs/npx.cmd','--yes','wrangler','secret','put','NEURAL_PUSH_SECRET'],
        cwd=ROOT/'free-wakeup-worker',input=config['secret']+'\n',text=True,check=True)
    script='''import pathlib,subprocess,tempfile,os
def configure(options):
    descriptor,name=tempfile.mkstemp(prefix='neural-push-')
    try:
        with os.fdopen(descriptor,'w') as handle:
            handle.write('NEURAL_PUSH_SECRET='+options['secret']+'\\nNEURAL_PUSH_URL='+options['url']+'\\n')
        subprocess.run(['sudo','-n','install','-m','600',name,'/etc/neural-api.env'],check=True)
    finally:pathlib.Path(name).unlink(missing_ok=True)
    subprocess.run(['sudo','-n','systemctl','restart','neural-api'],check=True)
    print('Push transport configured; no Google credential transferred; no notification sent.')
'''
    execute(script+'\nconfigure('+repr(config)+')\n',timeout=90)

if __name__=='__main__':main()
