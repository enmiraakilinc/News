"""Archive generated/history files without deleting originals or touching Git/config."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[2]
active_admin={'firebase_config.py','google_owner_session.py','audit_server_storage.py','check_storage_metric.py','cleanup_expired_chat_attachments.py','find_requested_video.py','verify_media_access.py','verify_chat_accounts.py','fcm_send.py','repair_firestore_pair.py'}
keep={'README.md','.gitignore','.mcp.json','firestore.rules','firebase-background-test.json','firebase-chat-update-test.json','firebase-local-test.json'}
mapping={}
for old in root.iterdir():
    if not old.is_file() or old.name in keep:continue
    name=old.name
    version=re.search(r'(?:Neural-Haber-|release-|release-notes-)(\d+\.\d+\.\d+)',name)
    if 'adminsdk' in name:folder='private/credentials'
    elif version:folder=f'artifacts/releases/{version.group(1)}'
    elif name.endswith('.py'):folder='tools/admin' if name in active_admin else 'archive/operations'
    elif name.startswith('build_release_'):folder='archive/releases/scripts'
    elif name.endswith(('.ps1','.bat','.txt')):folder='private/local-files'
    elif name.endswith('.rules') or name.endswith('.fragment'):folder='archive/rules'
    elif name.endswith('.json'):folder='private/backups'
    elif name.endswith('.md'):folder='docs/project'
    elif name.endswith(('.png','.jpg','.jpeg')):folder='assets/branding'
    elif name.endswith('.log'):folder='archive/logs'
    else:continue
    mapping[old]=root/folder/name
for old in (root/'flutter_application_1').glob('CHANGELOG_*.md'):
    mapping[old]=root/'docs/releases'/old.name
for old,new in mapping.items():
    if not old.resolve().is_relative_to(root) or not new.resolve().is_relative_to(root):raise RuntimeError('Path escaped workspace.')
    if new.exists():raise RuntimeError(f'Refusing to overwrite {new.name}')
for old,new in mapping.items():
    new.parent.mkdir(parents=True,exist_ok=True);old.rename(new)
(root/'tools/refactor/workspace-path-migration.json').write_text(json.dumps({str(k.relative_to(root)):str(v.relative_to(root)) for k,v in mapping.items()},indent=2),encoding='utf-8')
config=root/'tools/admin/firebase_config.py'
s=config.read_text(encoding='utf-8').replace('Path(__file__).resolve().parent','Path(__file__).resolve().parents[2]').replace("keys = list(ROOT.glob('*adminsdk*.json'))", "keys = list((ROOT / 'private/credentials').glob('*adminsdk*.json')) + list(ROOT.glob('*adminsdk*.json'))")
config.write_text(s,encoding='utf-8')
for name in ['firebase-background-test.json','firebase-chat-update-test.json','firebase-local-test.json']:
    path=root/name
    data=json.loads(path.read_text(encoding='utf-8'));data.setdefault('firestore',{})['rules']='firestore.rules';path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
test=root/'free-wakeup-worker/rules.test.mjs'
s=test.read_text(encoding='utf-8');s=re.sub(r"new URL\('../firestore-[^']+\.pending\.rules'", "new URL('../firestore.rules'",s);test.write_text(s,encoding='utf-8')
ignore=root/'.gitignore';s=ignore.read_text(encoding='utf-8');s+='\n# Local credentials, user-data backups and generated release archives.\nprivate/\nartifacts/\narchive/\n.venv/\n__pycache__/\n';ignore.write_text(s,encoding='utf-8')
print(f'Archived/moved {len(mapping)} files with a recovery path manifest; no files deleted.')
