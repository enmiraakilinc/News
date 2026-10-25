"""Apply the reviewed expiry migration without rebuilding APKs or restarting sync."""
from pathlib import Path
import json,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute
options={'sql':(ROOT/'server/sql/006_media_expiry.sql').read_text(encoding='utf-8'),
         'commit':(ROOT/'server/src/commit.mjs').read_text(encoding='utf-8'),
         'policy':(ROOT/'server/src/write_policy.mjs').read_text(encoding='utf-8')}
script='''import json,pathlib,subprocess,tempfile,os
def deploy(options):
 def run(args,**kw):return subprocess.run(args,check=True,text=True,**kw)
 run(['sudo','systemctl','start','neural-backup'])
 run(['sudo','install','-d','-m','700','/var/lib/neural-backups/media-expiry-before'])
 run(['sudo','cp','--no-clobber','/opt/neural/server/src/write_policy.mjs','/var/lib/neural-backups/media-expiry-before/write_policy.mjs'])
 with tempfile.TemporaryDirectory(prefix='neural_expiry_') as directory:
  folder=pathlib.Path(directory);policy=folder/'write_policy.mjs';policy.write_text(options['policy'])
  run(['node','--check',str(policy)])
  run(['sudo','-u','postgres','psql','-Xq','-v','ON_ERROR_STOP=1','-d','neural_haber'],input='BEGIN;'+options['sql']+'COMMIT;')
  run(['sudo','install','-m','644',str(policy),'/opt/neural/server/src/write_policy.mjs'])
  commit=folder/'commit.mjs';commit.write_text(options['commit'])
  run(['node','--check',str(commit)])
  run(['sudo','cp','--no-clobber','/opt/neural/server/src/commit.mjs','/var/lib/neural-backups/media-expiry-before/commit.mjs'])
  run(['sudo','install','-m','644',str(commit),'/opt/neural/server/src/commit.mjs'])
 run(['sudo','systemctl','restart','neural-api'])
 run(['sudo','systemctl','is-active','neural-api'])
 print(json.dumps({'expiryMigrationApplied':True,'apiRestarted':True,'sourceSyncUntouched':True}))
'''
execute(script+'\ndeploy('+repr(options)+')\n',timeout=300)
