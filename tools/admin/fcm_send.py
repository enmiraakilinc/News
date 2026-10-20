"""Neural Haber — 'updates' konusuna FCM push gönderir.
Kullanım:
  python fcm_send.py "Başlık" "Mesaj metni"
Varsayılan mesaj güncelleme bildirimidir. Servis hesabı anahtarı repo DIŞINDA.
"""
from firebase_config import PROJECT_ID, admin_key_path
import sys
import json
import urllib.request
import google.auth.transport.requests
from google.oauth2 import service_account

KEY = str(admin_key_path())
PROJECT = PROJECT_ID
TOPIC = "updates"
SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]

title = sys.argv[1] if len(sys.argv) > 1 else "Güncelleme"
body = sys.argv[2] if len(sys.argv) > 2 else "Yeni bir güncelleme mevcut. Uygulamayı güncelleyin."

creds = service_account.Credentials.from_service_account_file(KEY, scopes=SCOPES)
creds.refresh(google.auth.transport.requests.Request())

payload = {
    "message": {
        "topic": TOPIC,
        "notification": {"title": title, "body": body},
        "android": {
            "priority": "high",
            # Aynı collapse_key/tag ile gelen yeni bildirim eskisinin YERİNE geçer.
            # Böylece arka arkaya güncelleme çıksa bile telefonda tek bildirim kalır.
            "collapse_key": "neural_haber_update",
            "notification": {"tag": "neural_haber_update"},
        },
    }
}
data = json.dumps(payload).encode("utf-8")
req = urllib.request.Request(
    f"https://fcm.googleapis.com/v1/projects/{PROJECT}/messages:send",
    data=data,
    headers={
        "Authorization": f"Bearer {creds.token}",
        "Content-Type": "application/json; charset=utf-8",
    },
    method="POST",
)
try:
    with urllib.request.urlopen(req) as resp:
        print("OK", resp.status, resp.read().decode("utf-8"))
except urllib.error.HTTPError as e:
    print("HATA", e.code, e.read().decode("utf-8"))
