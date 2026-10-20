"""Owner-controlled local PC bridge. No BOT_TOKEN, admin key or cloud AI required.

Run only while you want remote control enabled. Code execution is opt-in.
"""
import argparse
import ast
import base64
from datetime import datetime, timezone
import getpass
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit


def windows_secret(path):
    """Read a current-user DPAPI-protected bridge secret; never print it."""
    import ctypes
    from ctypes import wintypes
    class Blob(ctypes.Structure):
        _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_byte))]
    raw = Path(path).read_bytes()
    buffer = ctypes.create_string_buffer(raw)
    source = Blob(len(raw), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_byte)))
    target = Blob()
    if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(source), None, None, None, None, 0, ctypes.byref(target)):
        raise RuntimeError('Yerel PC anahtarı bu Windows hesabıyla açılamadı.')
    try:
        return ctypes.string_at(target.data, target.size).decode('utf-8')
    finally:
        ctypes.windll.kernel32.LocalFree(target.data)


def inside(root, relative):
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise ValueError('Proje içindeki göreli dosya yolu gerekli.')
    target = (root / relative).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError('Proje dışındaki dosya izlenemez.')
    return target


def redact(text, secret):
    text = str(text).replace(secret, '[gizlendi]') if secret else str(text)
    return re.sub(r'\d{6,}:[A-Za-z0-9_-]{20,}|(?:sk-|ghp_|github_pat_)[A-Za-z0-9_-]+', '[gizlendi]', text)[:3500]


def run_process(arguments, root):
    # Do not pass the bridge token or cloud credentials to custom Python code.
    allowed = {'PATH', 'SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP', 'LANG', 'LOCALAPPDATA'}
    clean_env = {k: v for k, v in os.environ.items() if k.upper() in allowed}
    result = subprocess.run(arguments, cwd=root, env=clean_env, capture_output=True,
                            encoding='utf-8', errors='replace', timeout=25)
    output = (result.stdout + '\n' + result.stderr).strip()
    return f'Çıkış kodu: {result.returncode}\n{output or "Çıktı yok."}'[:3500]


def execute(job, root, allow_code=False, watch=None):
    kind, payload = job['kind'], job.get('payload', {})
    if kind == 'python':
        if not allow_code:
            return {'text': 'Python çalıştırma bu PC oturumunda kapalı. Ajanı --allow-code ile başlatırsan ayrıca izin vermiş olursun.'}
        code = payload.get('code')
        if not isinstance(code, str) or len(code) > 3000:
            raise ValueError('Geçersiz özel komut.')
        return {'text': run_process([sys.executable, '-I', '-c', code], root)}
    if kind == 'gitpull':
        location = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], cwd=root, text=True).strip()
        if Path(location).resolve() != root.resolve():
            raise ValueError('Kayıtlı klasör Git deposunun kökü değil. Otomatik pull yapılmadı.')
        remote = subprocess.check_output(['git', 'remote', 'get-url', 'origin'], cwd=root, text=True).strip()
        match = re.fullmatch(r'(?:https://github\.com/|git@github\.com:)([^/]+/[^/]+?)(?:\.git)?/?', remote)
        if not match or match.group(1).lower() != str(payload.get('repo', '')).lower():
            raise ValueError('Yerel Git deposu seçili projenin deposuyla eşleşmiyor.')
        return {'text': run_process(['git', 'pull', '--ff-only'], root)}
    if kind == 'watch':
        target = inside(root, payload.get('path'))
        if not target.is_file() or target.suffix.lower() not in {'.log', '.txt', '.py'}:
            raise ValueError('Mevcut .log, .txt veya .py dosyası seçilmeli.')
        if watch is not None:
            watch.update(path=str(target), stamp=0)
        return {'text': 'Dosya takibi seçildi. .py için yalnızca sözdizimi; günlük dosyası için yeni son bölüm raporlanır. Program otomatik başlatılmaz.'}
    if kind == 'screenshot':
        try:
            from PIL import ImageGrab
        except ImportError:
            return {'text': 'Ekran görüntüsü için bu PC ortamında Pillow kurulmalı.'}
        image = ImageGrab.grab().convert('RGB')
        image.thumbnail((1280, 1280))
        stream = io.BytesIO()
        image.save(stream, format='JPEG', quality=65)
        raw = stream.getvalue()
        if len(raw) > 600000:
            raise ValueError('Ekran görüntüsü boyutu çok büyük.')
        return {'text': 'İstenen ekran görüntüsü.', 'image': base64.b64encode(raw).decode(),
                'captured_at': datetime.now(timezone.utc).isoformat()}
    raise ValueError('Desteklenmeyen PC işlemi.')


def watch_error(root, watch):
    if not watch.get('path'):
        return None
    target = Path(watch['path']).resolve()
    if not target.is_relative_to(root.resolve()) or not target.is_file():
        return 'İzlenen dosya artık bulunamıyor.'
    stamp = target.stat().st_mtime_ns
    if stamp == watch.get('stamp'):
        return None
    watch['stamp'] = stamp
    if target.suffix.lower() == '.py':
        if target.stat().st_size > 1000000:
            return 'İzlenen Python dosyası sözdizimi kontrolü için çok büyük.'
        try:
            ast.parse(target.read_bytes())
            return 'Python sözdizimi kontrolü geçti; çalışma zamanı testi yapılmadı.'
        except (SyntaxError, UnicodeError):
            return 'İzlenen Python dosyasında sözdizimi/karakter kodlama hatası var.'
    with target.open('rb') as file:
        file.seek(max(0, target.stat().st_size - 3500))
        return file.read(3500).decode('utf-8', errors='replace')


class Bridge:
    def __init__(self, url, secret):
        parsed = urlsplit(url)
        if parsed.scheme != 'https' or not parsed.hostname or not parsed.hostname.endswith('.workers.dev') or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ['', '/']:
            raise ValueError('Cloudflare Worker HTTPS adresi gerekli.')
        self.url, self.secret = url.rstrip('/'), secret

    def post(self, path, data):
        request = urllib.request.Request(self.url + path, json.dumps(data).encode(),
                  {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + self.secret,
                   'User-Agent': 'ProjectAssistant/1.0'})
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if path == '/pc/result' and error.code == 404:
                return {'accepted': True, 'removed': True}
            raise RuntimeError(f'PC bağlantısı yanıtı: HTTP {error.code}') from None
        except Exception:
            raise RuntimeError('PC bağlantısı kurulamadı; daha sonra yeniden denenecek.') from None


def save(path, data):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    temp.replace(path)


def handle_job(bridge, project, root, job, journal, journal_path, allow_code, watcher, codex_config=None):
    key = project + ':' + job['id']
    saved = journal.get(key)
    if saved and saved.get('state') == 'done':
        result = {'text': 'Bu işlem daha önce tamamlandı; tekrar çalıştırılmadı.'}
    elif saved and saved.get('state') == 'started':
        result = {'text': 'Önceki deneme kesildi; işlemin etkisi belirsiz. Aynı kod veya git işlemi otomatik tekrarlanmadı.'}
    elif saved and saved.get('result'):
        result = saved['result']
    else:
        journal[key] = {'state': 'started'}
        save(journal_path, journal)
        try:
            if job['kind'] == 'codex':
                if not codex_config or project not in codex_config.get('codex_projects', []):
                    raise ValueError('Bu proje için yerel Codex bağlantısı etkin değil.')
                from codex_bridge import run_codex
                result = run_codex(job['payload']['prompt'], root, codex_config.get('codex_exe'),
                    lambda: bridge.post('/pc/heartbeat', dict(project=project, id=job['id'], lease=job['lease'])))
            else:
                result = execute(job, root, allow_code, watcher)
        except subprocess.TimeoutExpired:
            result = {'text': 'PC işlemi zaman sınırını aştı. Etkisi kontrol edilmeli; otomatik tekrarlanmayacak.'}
        except Exception as error:
            # Errors sent to Telegram may contain private paths; remove known tokens.
            result = {'text': redact(str(error), bridge.secret)}
        result['text'] = redact(result['text'], bridge.secret)
        journal[key] = {'state': 'ready', 'result': result}
        save(journal_path, journal)
    response = bridge.post('/pc/result', dict(project=project, id=job['id'], lease=job['lease'], **result))
    if response.get('accepted'):
        # Erase output/images locally after acknowledgment; retain only dedup ID.
        journal[key] = {'state': 'done'}
        save(journal_path, journal)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--allow-code', action='store_true')
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding='utf-8-sig'))
    secret = os.environ.get('PC_SECRET')
    if not secret and config.get('secret_file'):
        secret = windows_secret(config['secret_file'])
    secret = secret or getpass.getpass('PC_SECRET (gizli giriş): ')
    if len(secret) < 32:
        raise ValueError('PC_SECRET en az 32 karakter olmalı.')
    bridge = Bridge(config['worker_url'], secret)
    roots = {alias: Path(path).resolve() for alias, path in config['projects'].items()}
    if not roots or len(roots)>10 or any(not root.is_dir() for root in roots.values()):
        raise ValueError('1–10 mevcut proje klasörü tanımlanmalı.')
    journal_path = args.config.resolve().parent / '.pc-agent-state.json'
    # Fail rather than rerun jobs if the deduplication file is damaged.
    journal = json.loads(journal_path.read_text(encoding='utf-8')) if journal_path.exists() else {}
    watchers = {alias: {} for alias in roots}
    print('PC ajanı açık. Durdurmak için Ctrl+C. Python komutları: ' + ('açık' if args.allow_code else 'kapalı'))
    while True:
        for alias, root in roots.items():
            try:
                error = watch_error(root, watchers[alias])
                body = {'project': alias}
                if error:
                    body['error'] = redact(error, secret)
                job = bridge.post('/pc/ping', body).get('job')
                if job:
                    handle_job(bridge, alias, root, job, journal, journal_path, args.allow_code, watchers[alias], config)
            except Exception:
                print('Bir PC işlemi veya bağlantısı tamamlanamadı. Sonraki kontrolde yeniden denenecek; gizli değerler yazdırılmadı.')
        time.sleep(30)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('PC ajanı durduruldu.')
