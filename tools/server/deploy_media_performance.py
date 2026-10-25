"""Deploy backward-compatible binary media and optional presence after tests."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute
options={'files':{name:(ROOT/'server/src'/name).read_text(encoding='utf-8') for name in ['main.mjs','media_binary.mjs','presence.mjs','write_policy.mjs']},
 'sql':(ROOT/'server/sql/007_presence.sql').read_text(encoding='utf-8')}
script='''import pathlib,subprocess,tempfile,json
def deploy(options):
 def run(args,**kwargs):return subprocess.run(args,check=True,text=True,**kwargs)
 run(['sudo','systemctl','start','neural-backup'])
 backup='/var/lib/neural-backups/media-performance-before'
 run(['sudo','install','-d','-m','700',backup])
 with tempfile.TemporaryDirectory(prefix='neural_media_') as temporary:
  folder=pathlib.Path(temporary)
  for name,content in options['files'].items():
   path=folder/name;path.write_text(content);run(['node','--check',str(path)])
  run(['sudo','-u','postgres','psql','-Xq','-v','ON_ERROR_STOP=1','-d','neural_haber'],input='BEGIN;'+options['sql']+'COMMIT;')
  for name in options['files']:
   target='/opt/neural/server/src/'+name
   if subprocess.run(['sudo','test','-f',target]).returncode==0:run(['sudo','cp','--no-clobber',target,backup+'/'+name])
   run(['sudo','install','-m','644',str(folder/name),target])
 run(['sudo','systemctl','restart','neural-api'])
 run(['sudo','systemctl','is-active','neural-api'])
 print(json.dumps({'binaryMediaDeployed':True,'optionalPresenceDeployed':True,'migrationStateUnchanged':True}))
'''
execute(script+'\ndeploy('+repr(options)+')\n',timeout=300)
