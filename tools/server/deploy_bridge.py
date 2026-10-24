"""Deploy reviewed server files and the mirror credential using encrypted SSH."""
from pathlib import Path
import argparse,base64,io,json,sys,tarfile
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute
parser=argparse.ArgumentParser()
parser.add_argument('--api-only',action='store_true')
parser.add_argument('--read-only-credential',type=Path)
args=parser.parse_args()
if not args.api_only and not args.read_only_credential:
    parser.error('Specify --api-only or the explicitly approved read-only credential file.')
if not args.api_only:
    identity=json.loads(args.read_only_credential.read_text(encoding='utf-8'))
    if identity.get('project_id')!='star-galeri' or identity.get('client_email')!='neural-pg-reader@star-galeri.iam.gserviceaccount.com':
        parser.error('Only the explicitly approved dedicated read-only identity is accepted.')
payload=io.BytesIO()
with tarfile.open(fileobj=payload,mode='w:gz') as archive:
    for relative in ('package.json','package-lock.json'):
        archive.add(ROOT/'server'/relative,arcname=relative)
    for path in (ROOT/'server/src').glob('*.mjs'):
        archive.add(path,arcname='src/'+path.name)
options={
 'archive':base64.b64encode(payload.getvalue()).decode(),
 'credential':None if args.api_only else args.read_only_credential.read_text(encoding='utf-8'),
 'sql':[(ROOT/'server/sql'/name).read_text(encoding='utf-8') for name in ('001_documents.sql','002_read_access.sql','003_primary_writes.sql','004_retention.sql','005_services.sql')],
 'nginx':(ROOT/'server/deploy/nginx.conf').read_text(encoding='utf-8'),
}
# The credential is transmitted on SSH stdin, never command arguments or logs.
execute((ROOT/'tools/server/deploy_remote.py').read_text(encoding='utf-8')+'\ndeploy('+repr(options)+')\n',timeout=1200)
