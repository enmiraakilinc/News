"""One-time authorized migration of the owner's existing bot.

Does not change subscriptions, paid plans, or the app release. Run only after
reviewing the tested Worker and receiving explicit migration authorization.
"""
import ast
import base64
import ctypes
from ctypes import wintypes
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BOT = ROOT/'tools/telegram-cloud-bot'
PRIVATE = ROOT/'private/credentials'
BACKUP = ROOT/'private/backups/telegram-cloud-migration'
GH = 'C:/Program Files/GitHub CLI/gh.exe'


def gh(*args, body=None):
    r = subprocess.run([GH,*args],input=json.dumps(body) if body is not None else None,
                       text=True,encoding='utf-8',capture_output=True)
    if r.returncode: raise RuntimeError('GitHub request failed; credentials not printed.')
    return json.loads(r.stdout) if r.stdout.strip() else None


def cli(*args, data=None):
    r = subprocess.run(['npx.cmd','--yes','wrangler@4',*args],cwd=BOT,
                       input=data,text=True,encoding='utf-8',capture_output=True)
    if r.returncode: raise RuntimeError('Cloudflare request failed; raw diagnostics withheld.')
    return r.stdout


def protect(data):
    class Blob(ctypes.Structure):
        _fields_=[('size',wintypes.DWORD),('data',ctypes.POINTER(ctypes.c_byte))]
    raw=data.encode();buffer=ctypes.create_string_buffer(raw)
    source=Blob(len(raw),ctypes.cast(buffer,ctypes.POINTER(ctypes.c_byte)));target=Blob()
    if not ctypes.windll.crypt32.CryptProtectData(ctypes.byref(source),None,None,None,None,0,ctypes.byref(target)):
        raise RuntimeError('Windows protection failed.')
    try:return ctypes.string_at(target.data,target.size)
    finally:ctypes.windll.kernel32.LocalFree(target.data)


def telegram(token,method,body=None):
    request=urllib.request.Request('https://api.telegram.org/bot'+token+'/'+method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(request,timeout=35) as r: d=json.load(r)
        if not d.get('ok'):raise RuntimeError('Telegram rejected request.')
        return d['result']
    except Exception:raise RuntimeError('Telegram request failed; token not printed.') from None


def main():
    PRIVATE.mkdir(parents=True,exist_ok=True);BACKUP.mkdir(parents=True,exist_ok=True)
    source=gh('api','repos/kunduracimelek/bot/contents/bot.py')
    original=base64.b64decode(source['content']).decode('utf-8-sig')
    values={}
    for n in ast.walk(ast.parse(original)):
        if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute) and n.func.attr=='getenv' and len(n.args)>1 and all(isinstance(a,ast.Constant) for a in n.args[:2]):
            values[n.args[0].value]=n.args[1].value
    token=values.get('BOT_TOKEN');owner=str(values.get('ADMIN_CHAT_ID',''))
    if not token or not owner.isdigit():raise RuntimeError('Existing owner configuration missing.')
    me=telegram(token,'getMe')
    if me.get('username')!='daisyschuster_bot':raise RuntimeError('Unexpected bot identity.')
    print('Existing bot identity verified.',flush=True)
    backup=BACKUP/'render-bot-before-migration.py'
    if not backup.exists():backup.write_text(original,encoding='utf-8')
    state_path=PRIVATE/'telegram-bot-state.dpapi'
    sys.path.insert(0,str(BOT))
    from pc_agent import windows_secret
    if state_path.exists(): state=json.loads(windows_secret(state_path))
    else:
        state={'BOT_TOKEN':token,'OWNER_ID':owner,'PC_SECRET':secrets.token_urlsafe(36),
          'WEBHOOK_SECRET':hmac.new(token.encode(),b'project-assistant-webhook-v1',hashlib.sha256).hexdigest()}
        state_path.write_bytes(protect(json.dumps(state)))
    if state['BOT_TOKEN']!=token:raise RuntimeError('Bot token changed; migration state needs review.')
    config=BOT/'wrangler.toml';text=config.read_text(encoding='utf-8')
    if 'REPLACE_WITH_CREATED_DATABASE_ID' in text:
        out=cli('d1','create','telegram-project-assistant','--update-config=false')
        match=re.search(r'database_id[\"\']?\s*[:=]\s*[\"\']([a-f0-9-]{36})[\"\']',out)
        if not match:raise RuntimeError('Created D1 ID could not be parsed; inspect dashboard before retry.')
        text=text.replace('REPLACE_WITH_CREATED_DATABASE_ID',match.group(1));config.write_text(text,encoding='utf-8')
    cli('d1','execute','telegram-project-assistant','--remote','--file=schema.sql')
    print('Dedicated D1 schema ready; no subscription changes requested.',flush=True)
    deploy=cli('deploy')
    urls=re.findall(r'https://telegram-project-assistant\.[a-z0-9-]+\.workers\.dev',deploy)
    if not urls:raise RuntimeError('Worker URL missing from deployment output.')
    url=urls[0]
    cli('secret','bulk',data=json.dumps(state))
    print('Worker and protected secrets deployed.',flush=True)
    # Map known local repos; the app's source repo is discovered without exposing credentials.
    local_app=ROOT/'flutter_application_1'
    remote=subprocess.run(['git','-c',f'safe.directory={local_app.as_posix()}','remote','get-url','origin'],cwd=local_app,text=True,capture_output=True).stdout.strip()
    match=re.fullmatch(r'(?:https://github\.com/|git@github\.com:)([^/]+/[^/]+?)(?:\.git)?/?',remote)
    app_repo=match.group(1) if match else 'enschumacher/Neural-Haber'
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',app_repo):raise RuntimeError('Unexpected app repository.')
    seed=BACKUP/'seed.sql'
    seed.write_text("INSERT OR IGNORE INTO projects(alias,repo) VALUES('uygulama','"+app_repo+"');\nINSERT OR IGNORE INTO projects(alias,repo) VALUES('bot','kunduracimelek/bot');\nINSERT OR IGNORE INTO projects(alias,repo) VALUES('eski-notlar','kunduracimelek/bot');\nINSERT OR IGNORE INTO settings(key,value) VALUES('selected','uygulama');\n",encoding='utf-8')
    cli('d1','execute','telegram-project-assistant','--remote','--file='+str(seed))
    # Transition the existing Render service on its next automatic GitHub deployment.
    # Keep old source/functions for rollback, but block the unauthenticated PC endpoint.
    marker='# CLOUD_PROJECT_ASSISTANT_TRANSITION_V1'
    if marker not in original:
        tree=ast.parse(original)
        guard=next(n for n in tree.body if isinstance(n,ast.If) and isinstance(n.test,ast.Compare) and isinstance(n.test.left,ast.Name) and n.test.left.id=='__name__')
        original_prefix='\n'.join(original.splitlines()[:guard.lineno-1])+'\n'
        suffix=f'''
{marker}
import hashlib as _hashlib
import hmac as _hmac
import requests as _requests
_CLOUD_URL = {url!r}
_EXPECTED_BOT = {me['id']!r}
_TRANSFER_SECRET = _hmac.new(TOKEN.encode(), b'project-assistant-webhook-v1', _hashlib.sha256).hexdigest()

@flask_app.before_request
def _protect_legacy_bridge():
    if request.path not in ['/', '/legacy-export']:
        return jsonify({{'error': 'use_authenticated_cloud_agent'}}), 410
    if request.path == '/legacy-export' and not _hmac.compare_digest(request.headers.get('Authorization', ''), 'Bearer ' + _TRANSFER_SECRET):
        return jsonify({{'error':'forbidden'}}), 403

@flask_app.route('/legacy-export', methods=['GET'])
def _export_legacy_state():
    return jsonify({{'notes': json_oku(YAPILACAKLAR_DOSYASI, []), 'commands': json_oku(KOMUT_DOSYASI, {{}}), 'settings': AYARLAR}})

def _activate_cloud_webhook():
    for _attempt in range(12):
        try:
            _me = _requests.get('https://api.telegram.org/bot' + TOKEN + '/getMe', timeout=20).json()
            if _me.get('result', {{}}).get('id') != _EXPECTED_BOT:
                return
            _r = _requests.post('https://api.telegram.org/bot' + TOKEN + '/setWebhook', json={{
                'url': _CLOUD_URL + '/telegram', 'secret_token': _TRANSFER_SECRET,
                'max_connections': 1, 'allowed_updates': ['message', 'callback_query'],
                'drop_pending_updates': False}}, timeout=25)
            if _r.ok and _r.json().get('ok'):
                return
        except Exception:
            pass
        time.sleep(10)

if __name__ == '__main__':
    threading.Thread(target=_activate_cloud_webhook, daemon=True).start()
    print('CLOUD_PROJECT_ASSISTANT_TRANSITION_V1', flush=True)
    run_flask()
'''
        changed=original_prefix+suffix
        ast.parse(changed)
        result=gh('api','--method','PUT','repos/kunduracimelek/bot/contents/bot.py','--input','-',body={
          'message':'Connect existing bot to persistent project assistant',
          'content':base64.b64encode(changed.encode()).decode(),'sha':source['sha'],'branch':'main'})
        print('Render transition committed:',result['commit']['sha'][:12],flush=True)
    else:print('Render transition already committed.',flush=True)
    (PRIVATE/'telegram-pc-secret.dpapi').write_bytes(protect(state['PC_SECRET']))
    pc_config={'worker_url':url,'secret_file':str(PRIVATE/'telegram-pc-secret.dpapi'),
      'projects':{'uygulama':str(local_app),'bot':'C:/Users/mkund/Desktop/telegram-bulut-bot'}}
    (PRIVATE/'telegram-pc-config.json').write_text(json.dumps(pc_config,indent=2),encoding='utf-8')
    report={'worker':url,'bot_username':me['username'],'github_transition_prepared':True,
      'no_subscription_changes':True,'webhook_verified':False,'pc_verified':False,
      'ai_agent_connected':False,'app_source_repository_verified':bool(match)}
    (BACKUP/'migration-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('Provisioning complete. Awaiting Render auto-deployment and final verification.',flush=True)


if __name__=='__main__':
    try:main()
    except Exception as error:
        print('Migration stopped: '+str(error),file=sys.stderr)
        sys.exit(1)
