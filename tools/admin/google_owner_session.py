"""Firebase ve veri bakımı için elle çalıştırılan betik. Dosya: google_owner_session.py. Use existing owner CLI authorization without printing tokens or credentials."""
import json
import subprocess
import time
from pathlib import Path
import requests

def owner_session():
    home = Path.home()
    config = json.loads((home / '.config' / 'configstore' / 'firebase-tools.json').read_text())
    tokens = config.get('tokens', {})
    token = tokens.get('access_token')
    if not token or tokens.get('expires_at', 0) < time.time()*1000+60000:
        matches = sorted((home / '.npm' / '_npx').glob('*/node_modules/firebase-tools/lib/configstore.js'))
        if not matches:
            raise SystemExit('firebase-tools kurulumu bulunamadı.')
        base = json.dumps(matches[0].parent.as_posix() + '/')
        script = "const base="+base+";const c=require(base+'configstore.js').configstore;require(base+'auth.js').getAccessToken(c.get('tokens').refresh_token,['https://www.googleapis.com/auth/cloud-platform']).then(t=>process.stdout.write(t.access_token)).catch(()=>process.exit(1));"
        r = subprocess.run(['node', '-e', script], capture_output=True, encoding='utf-8', errors='replace', timeout=40)
        assert r.returncode == 0 and r.stdout.startswith('ya29.'), 'Owner login refresh required; raw output withheld.'
        token = r.stdout.strip()
    session = requests.Session()
    session.headers['Authorization'] = 'Bearer ' + token
    return session
