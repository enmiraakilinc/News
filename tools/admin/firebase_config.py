"""Read technical Firebase identifiers from the existing app configuration."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT_ID = json.loads((ROOT / 'flutter_application_1/android/app/google-services.json').read_text(encoding='utf-8'))['project_info']['project_id']

def admin_key_path():
    keys = list((ROOT / 'private/credentials').glob('*adminsdk*.json')) + list(ROOT.glob('*adminsdk*.json'))
    if not keys:
        raise FileNotFoundError('Firebase yönetim anahtarı bulunamadı.')
    return max(keys, key=lambda path: path.stat().st_mtime)
