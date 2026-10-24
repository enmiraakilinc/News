"""Install the bridge in a separate directory; never mutate Firebase records."""
import base64
from pathlib import Path
import os, subprocess, tarfile, io, json
def deploy(options):
    def run(*args,**kwargs):
        return subprocess.run(args,check=True,stdout=subprocess.DEVNULL,**kwargs)
    def root_file(path,content,mode=0o644):
        temp=Path('/tmp')/('neural-'+os.urandom(8).hex())
        temp.write_text(content,encoding='utf-8');temp.chmod(0o600)
        try: run('sudo','-n','install','-D','-m',oct(mode)[2:],str(temp),path)
        finally:temp.unlink(missing_ok=True)
    for user in ('neural_api','neural_sync'):
        if subprocess.run(['id',user],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:
            run('sudo','-n','useradd','--system','--no-create-home','--shell','/sbin/nologin',user)
    run('sudo','-n','mkdir','-p','/opt/neural/server','/etc/neural')
    run('sudo','-n','chmod','750','/etc/neural')
    run('sudo','-n','chgrp','neural_sync','/etc/neural')
    # The only persisted credential belongs to the private mirror service.
    if options.get('credential'):
        root_file('/etc/neural/firebase-admin.json',options['credential'],0o640)
        run('sudo','-n','chgrp','neural_sync','/etc/neural/firebase-admin.json')
    archive=tarfile.open(fileobj=io.BytesIO(base64.b64decode(options['archive'])),mode='r:gz')
    for member in archive:
        if not member.isfile():continue
        relative=Path(member.name)
        if relative.is_absolute() or '..' in relative.parts:raise RuntimeError('unsafe_archive_path')
        root_file('/opt/neural/server/'+member.name,archive.extractfile(member).read().decode('utf-8'))
    sql='\n'.join(options['sql'])
    run('sudo','-n','-u','postgres','psql','-Xq','-v','ON_ERROR_STOP=1','-d','neural_haber',input=sql,text=True)
    run('sudo','-n','npm','ci','--omit=dev','--ignore-scripts','--no-audit','--no-fund',cwd='/opt/neural/server')
    common="""[Unit]
After=network-online.target postgresql.service
Wants=network-online.target
Requires=postgresql.service
StartLimitIntervalSec=600
StartLimitBurst=3

[Service]
WorkingDirectory=/opt/neural/server
Environment=NODE_ENV=production
Environment=FIREBASE_PROJECT_ID=star-galeri
Restart=on-failure
RestartSec=10
TimeoutStopSec=25
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
CapabilityBoundingSet=
LockPersonality=true
UMask=0077

[Install]
WantedBy=multi-user.target
"""
    api=common.replace('[Service]','[Service]\nUser=neural_api\nGroup=neural_api\nMemoryMax=700M\nExecStart=/usr/bin/node /opt/neural/server/src/main.mjs')
    sync=common.replace('[Service]','[Service]\nUser=neural_sync\nGroup=neural_sync\nMemoryMax=2500M\nEnvironment=GOOGLE_APPLICATION_CREDENTIALS=/etc/neural/firebase-admin.json\nExecStart=/usr/bin/node /opt/neural/server/src/mirror.mjs')
    root_file('/etc/systemd/system/neural-api.service',api)
    root_file('/etc/systemd/system/neural-sync.service',sync)
    root_file('/etc/nginx/nginx.conf',options['nginx'])
    run('sudo','-n','nginx','-t')
    run('sudo','-n','systemctl','daemon-reload')
    run('sudo','-n','systemctl','enable','neural-api')
    run('sudo','-n','systemctl','restart','neural-api')
    if options.get('credential'):
        run('sudo','-n','systemctl','enable','neural-sync')
        run('sudo','-n','systemctl','restart','neural-sync')
    run('sudo','-n','systemctl','reload','nginx')
    print(json.dumps({'deployed':True,'applicationCutover':False,'firestoreModified':False,'api':'https://138.2.185.151','mode':'read-migration-bridge','mirrorStarted':bool(options.get('credential'))}))
