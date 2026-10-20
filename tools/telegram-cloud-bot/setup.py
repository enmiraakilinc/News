"""Provision only this new bot Worker; activate only after Render polling stops.

No credentials are read from the old source code. Secret inputs are never printed.
"""
import argparse
import getpass
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parent


def wrangler(*args, secret=None):
    command = ['npx.cmd' if os.name == 'nt' else 'npx', '--yes', 'wrangler@4', *args]
    result = subprocess.run(command, cwd=ROOT, input=secret, text=True,
                            encoding='utf-8', capture_output=True)
    if result.returncode:
        # Wrangler diagnostics can include environment/config secrets.
        raise RuntimeError('Cloudflare işlemi başarısız. Oturum ve D1 yapılandırmasını kontrol et.')
    return result.stdout


def get_secret(name):
    value = os.environ.get(name) or getpass.getpass(f'{name} (gizli giriş): ')
    if not value.strip():
        raise ValueError(f'{name} boş bırakılamaz.')
    return value.strip()


def telegram(token, method, body):
    req = urllib.request.Request(
        f'https://api.telegram.org/bot{token}/{method}',
        data=json.dumps(body).encode(),
        headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=40) as response:
            data = json.load(response)
    except Exception:
        raise RuntimeError('Telegram yapılandırma isteği başarısız; anahtar çıktıya yazılmadı.') from None
    if not data.get('ok'):
        raise RuntimeError('Telegram yapılandırmayı kabul etmedi.')
    return data['result']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--provision', action='store_true')
    group.add_argument('--activate', metavar='WORKER_HTTPS_URL')
    group.add_argument('--rollback', action='store_true')
    parser.add_argument('--render-stopped', action='store_true')
    args = parser.parse_args()
    if args.provision:
        config = ROOT / 'wrangler.toml'
        text = config.read_text(encoding='utf-8')
        if 'REPLACE_WITH_CREATED_DATABASE_ID' in text:
            output = wrangler('d1', 'create', 'telegram-project-assistant', '--update-config=false')
            match = re.search(r'database_id[\"\']?\s*[:=]\s*[\"\']([a-f0-9-]{36})[\"\']', output)
            if not match:
                raise RuntimeError('D1 kimliği bulunamadı. Veritabanını panelden kontrol et; otomatik yeniden oluşturma yapılmadı.')
            identifier = match.group(1)
            config.write_text(text.replace('REPLACE_WITH_CREATED_DATABASE_ID', identifier), encoding='utf-8')
        wrangler('d1', 'execute', 'telegram-project-assistant', '--remote', '--file=schema.sql')
        for name in ['BOT_TOKEN', 'OWNER_ID', 'WEBHOOK_SECRET', 'PC_SECRET']:
            value = get_secret(name)
            if name in ['WEBHOOK_SECRET', 'PC_SECRET'] and not re.fullmatch(r'[A-Za-z0-9_-]{32,256}', value):
                raise ValueError(f'{name}: 32–256 URL-güvenli rastgele karakter gerekli.')
            if name == 'OWNER_ID' and not value.isdigit():
                raise ValueError('OWNER_ID sayısal Telegram kullanıcı kimliği olmalı.')
            wrangler('secret', 'put', name, secret=value+'\n')
        if os.environ.get('GITHUB_TOKEN'):
            wrangler('secret', 'put', 'GITHUB_TOKEN', secret=os.environ['GITHUB_TOKEN']+'\n')
        wrangler('deploy')
        print('Yeni bot Worker hazırlandı. Render ve Telegram bağlantısı değiştirilmedi.')
        print('Cloudflare panelinden Worker adresini al. Render durdurulduktan sonra --activate kullan.')
    elif args.activate:
        from urllib.parse import urlsplit
        url = urlsplit(args.activate)
        if url.scheme != 'https' or not url.hostname or not url.hostname.endswith('.workers.dev') or url.username or url.password or url.query or url.fragment or url.path not in ['', '/']:
            raise ValueError('Cloudflare panelindeki tam https://...workers.dev adresini kullan.')
        if not args.render_stopped:
            raise ValueError('Önce eski Render polling servisini durdur. Ardından --render-stopped ile tekrar çalıştır.')
        token = get_secret('BOT_TOKEN')
        secret = get_secret('WEBHOOK_SECRET')
        endpoint = args.activate.rstrip('/') + '/telegram'
        telegram(token, 'setWebhook', {'url': endpoint, 'secret_token': secret,
                 'max_connections': 1, 'allowed_updates': ['message', 'callback_query'],
                 'drop_pending_updates': False})
        info = telegram(token, 'getWebhookInfo', {})
        if info.get('url') != endpoint:
            raise RuntimeError('Webhook adresi doğrulanamadı.')
        print('Webhook adresi doğrulandı. Bu kontrol Telegram komutunun çalıştığını tek başına kanıtlamaz; /start ile dene.')
    else:
        telegram(get_secret('BOT_TOKEN'), 'deleteWebhook', {'drop_pending_updates': False})
        print('Webhook kaldırıldı. Eski Render servisini yeniden başlatabilirsin. D1 kayıtları silinmedi.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Do not dump traceback, HTTP request URLs, subprocess arguments or tokens.
        print(f'Kurulum tamamlanmadı: {error}', file=sys.stderr)
        sys.exit(1)
