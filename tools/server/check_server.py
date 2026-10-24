"""Non-destructive access checks, protected backup install and aggregate status."""
from pathlib import Path
import sys,json
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.ssh_admin import execute
options={'sql':(ROOT/'server/test/rls.sql').read_text(),'backup':(ROOT/'server/deploy/backup.py').read_text()}
script=r"""
from pathlib import Path
import subprocess,json,os
def check(o):
    result=subprocess.run(['sudo','-n','-u','postgres','psql','-XqAt','-v','ON_ERROR_STOP=1','-d','neural_haber'],input=o['sql'],text=True,capture_output=True)
    if result.returncode:
        # Fixtures contain no live content; print only the assertion/error name.
        print(json.dumps({'rlsChecksPassed':False,'error':result.stderr[-1000:]}))
        raise SystemExit(1)
    print(json.dumps({'rlsChecksPassed':'rls_checks_passed' in result.stdout,'fixturesRolledBack':True}))
    def install(path,text,mode):
        p=Path('/tmp/neural-reviewed-'+os.urandom(8).hex());p.write_text(text);p.chmod(0o600)
        try:subprocess.run(['sudo','-n','install','-D','-m',mode,str(p),path],check=True)
        finally:p.unlink(missing_ok=True)
    install('/opt/neural/server/backup.py',o['backup'],'700')
    install('/etc/systemd/system/neural-backup.service','[Unit]\nAfter=postgresql.service\nRequires=postgresql.service\n[Service]\nType=oneshot\nUser=root\nExecStart=/usr/bin/python3 /opt/neural/server/backup.py\nUMask=0077\n','644')
    install('/etc/systemd/system/neural-backup.timer','[Unit]\nDescription=Daily PostgreSQL backup\n[Timer]\nOnCalendar=*-*-* 02:30:00 UTC\nRandomizedDelaySec=600\nPersistent=true\n[Install]\nWantedBy=timers.target\n','644')
    subprocess.run(['sudo','-n','systemctl','daemon-reload'],check=True)
    subprocess.run(['sudo','-n','systemctl','enable','--now','neural-backup.timer'],check=True)
    rows=subprocess.check_output(['sudo','-n','-u','postgres','psql','-XqAt','-d','neural_haber','-c',"SELECT json_build_object('documents',count(*),'bytes',pg_database_size(current_database())) FROM neural.documents"],text=True)
    print(rows.strip())
check(OPTIONS)
"""
execute(script.replace('OPTIONS',repr(options)),timeout=180)
