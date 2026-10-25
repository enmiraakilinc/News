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


def admin_session():
    """Use a local service key when available, otherwise the existing owner CLI login."""
    # Optional, process-local correction for maintenance on a mis-set PC clock.
    # Never changes Windows time or authentication checks on the application.
    import os
    if os.environ.get('NEURAL_GOOGLE_CLOCK_FROM_HTTPS') == '1':
        import time
        import requests
        from email.utils import parsedate_to_datetime
        from datetime import timedelta, timezone
        from google.auth import _helpers
        response = requests.head('https://oauth2.googleapis.com/token',
                                 headers={'Cache-Control': 'no-cache'}, timeout=20)
        instant = parsedate_to_datetime(response.headers['Date']).astimezone(timezone.utc).replace(tzinfo=None)
        started = time.monotonic()
        _helpers.utcnow = lambda: instant + timedelta(seconds=time.monotonic() - started)
    try:
        key = admin_key_path()
    except FileNotFoundError:
        from tools.admin.google_owner_session import owner_session
        return owner_session()
    from google.oauth2 import service_account
    from google.auth.transport.requests import AuthorizedSession
    return AuthorizedSession(service_account.Credentials.from_service_account_file(
        str(key), scopes=['https://www.googleapis.com/auth/cloud-platform']))
