"""Scoped local ChatGPT-authenticated Codex jobs; no API-key fallback."""
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path


def run_codex(prompt, root, executable=None, heartbeat=lambda: None):
    exe = executable or shutil.which('codex')
    if not exe:
        raise RuntimeError('Bu bilgisayarda Codex bulunamadı.')
    allowed = {'PATH', 'SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP', 'USERPROFILE',
               'HOMEDRIVE', 'HOMEPATH', 'APPDATA', 'LOCALAPPDATA', 'CODEX_HOME', 'LANG'}
    env = {k: v for k, v in os.environ.items() if k.upper() in allowed}
    # pythonw has no console; Windows otherwise creates one for codex.exe.
    process_options = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
    auth = subprocess.run([exe, 'login', 'status'], env=env, capture_output=True,
                          text=True, timeout=30, **process_options)
    if auth.returncode or 'chatgpt' not in (auth.stdout + auth.stderr).lower():
        raise RuntimeError('Codex için bilgisayarda ChatGPT hesabınla giriş yapmalısın. API ile ücretli bağlantı kurulmadı.')
    instruction = ('Work only in the selected project. Preserve existing changes. '
                   'Implement and test the request. Do not publish, deploy, read credentials, '
                   'or enable paid services. Reply concisely in Turkish. Request:\n' + prompt)
    with tempfile.TemporaryDirectory(prefix='telegram-codex-') as temporary:
        output = Path(temporary) / 'answer.txt'
        with open(Path(temporary) / 'events.jsonl', 'w', encoding='utf-8') as events:
            process = subprocess.Popen([
                exe, 'exec', '--json', '--ephemeral', '--ignore-user-config',
                '-c', 'forced_login_method="chatgpt"',
                '--approve-for-me', '--cd', str(root), '--output-last-message', str(output), '-'
            ], stdin=subprocess.PIPE, stdout=events, stderr=events, env=env, **process_options)
            process.stdin.write(instruction.encode('utf-8'))
            process.stdin.close()
            deadline = time.monotonic() + 900
            try:
                while process.poll() is None:
                    if time.monotonic() > deadline:
                        raise TimeoutError('Kod görevi 15 dakika sınırını aştı; değişiklikleri kontrol et.')
                    time.sleep(5)
                    heartbeat()
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)
        if process.returncode:
            raise RuntimeError('Codex görevi tamamlanamadı. Bilgisayarda Codex oturumunu ve kullanım kotanı kontrol et; otomatik tekrar çalıştırılmadı.')
        return {'text': output.read_text(encoding='utf-8')[:3500] if output.exists() else 'Kod görevi tamamlandı; proje dosyalarını kontrol et.'}
