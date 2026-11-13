"""Proje bakım betiği. Dosya: runtime_config.py."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def load_env():
    env = ROOT / '.env'
    if not env.is_file():
        return
    for line in env.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))

def require(name):
    load_env()
    value = os.environ.get(name, '').strip()
    if not value:
        raise SystemExit(name + ' .env içinde tanımlı değil.')
    return value

def public_url():
    return require('NEURAL_PUBLIC_URL').rstrip('/')

def ssh_host():
    return require('NEURAL_SSH_HOST')

def ssh_key():
    raw = require('NEURAL_SSH_KEY')
    path = Path(raw).expanduser()
    return path if path.is_absolute() else Path.home() / path

def releases_dir():
    load_env()
    return os.environ.get('NEURAL_RELEASES_DIR', '/var/lib/neural/releases').rstrip('/\\')

def bot_dir():
    load_env()
    raw = os.environ.get('NEURAL_BOT_DIR', '').strip()
    return raw or str(Path.home() / 'telegram-bulut-bot')
