#!/usr/bin/python3
"""Local backup protected by filesystem permissions; no content in logs."""
from pathlib import Path
from datetime import datetime,timezone
import json,os,subprocess
ROOT=Path('/var/lib/neural-backups')
ROOT.mkdir(mode=0o700,parents=True,exist_ok=True)
os.chmod(ROOT,0o700)
space=os.statvfs(ROOT)
used=1-space.f_bavail/space.f_blocks
if used>=0.80:
    print(json.dumps({'event':'backup_disk_warning','usedPercent':round(used*100,1)}))
    raise SystemExit(1)
stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
destination=ROOT/('neural-haber-'+stamp+'.dump')
temp=destination.with_suffix('.tmp')
os.umask(0o077)
try:
    with temp.open('wb') as output:
        subprocess.run(['sudo','-n','-u','postgres','pg_dump','-Fc','--no-owner','--no-acl','neural_haber'],stdout=output,check=True)
        output.flush();os.fsync(output.fileno())
    subprocess.run(['pg_restore','--list',str(temp)],stdout=subprocess.DEVNULL,check=True)
    temp.replace(destination)
except BaseException:
    temp.unlink(missing_ok=True)
    raise
backups=sorted((p for p in ROOT.glob('neural-haber-*.dump') if p.is_file() and not p.is_symlink()),reverse=True)
for old in backups[7:]:
    if old.resolve().parent==ROOT.resolve():old.unlink()
print(json.dumps({'event':'backup_complete','bytes':destination.stat().st_size,'retained':min(len(backups),7)}))
