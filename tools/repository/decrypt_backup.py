"""Decrypt a verified local backup. The recovery key must stay outside GitHub."""
import argparse
import base64
import json
import hashlib
from pathlib import Path
import shutil
import tempfile
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

MAGIC = b'NHBACKUP1\0'

def decrypt(archive, key_file, output):
    archive, key_file, output = map(Path, (archive, key_file, output))
    if archive.suffix == '.json':
        return decrypt_parts(archive, key_file, output)
    if output.exists():
        raise FileExistsError('Output already exists; choose a new path.')
    key = base64.b64decode(key_file.read_bytes().strip(), validate=True)
    if len(key) != 32:
        raise ValueError('Recovery key must contain 32 bytes, base64 encoded.')
    size = archive.stat().st_size
    if size < len(MAGIC) + 12 + 16:
        raise ValueError('Invalid backup format.')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with archive.open('rb') as src:
            header = src.read(len(MAGIC) + 12)
            if not header.startswith(MAGIC):
                raise ValueError('Unsupported backup format.')
            src.seek(-16, 2)
            tag = src.read(16)
            src.seek(len(header))
            cipher = Cipher(algorithms.AES(key), modes.GCM(header[-12:], tag)).decryptor()
            cipher.authenticate_additional_data(header)
            remaining = size - len(header) - 16
            with tempfile.NamedTemporaryFile(dir=output.parent, prefix='.backup-decrypt-', delete=False) as dest:
                temporary = Path(dest.name)
                while remaining:
                    chunk = src.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise ValueError('Backup is truncated.')
                    remaining -= len(chunk)
                    dest.write(cipher.update(chunk))
                dest.write(cipher.finalize())
        # Authentication succeeded. Do not overwrite any existing file.
        with temporary.open('rb') as src, output.open('xb') as dest:
            shutil.copyfileobj(src, dest, length=1024 * 1024)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def decrypt_parts(manifest_file, key_file, output):
    manifest = json.loads(manifest_file.read_text(encoding='utf-8'))
    if manifest.get('format') != 'neural-encrypted-backup-parts-v1':
        raise ValueError('Unsupported parts manifest.')
    archive_name = manifest['archive']
    if '/' in archive_name or chr(92) in archive_name or not archive_name.endswith('.zip.enc'):
        raise ValueError('Invalid archive name.')
    if not 1 <= len(manifest['parts']) <= 1000:
        raise ValueError('Invalid part count.')
    if output.exists():
        raise FileExistsError('Output already exists; choose a new path.')
    output.parent.mkdir(parents=True, exist_ok=True)
    joined = None
    try:
        total = hashlib.sha256()
        size = 0
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix='.backup-join-', delete=False) as dest:
            joined = Path(dest.name)
            for index, entry in enumerate(manifest['parts'], 1):
                if entry['name'] != f'{archive_name}.part{index:03d}':
                    raise ValueError('Invalid part name or ordering.')
                part = manifest_file.parent / entry['name']
                digest = hashlib.sha256()
                part_size = 0
                with part.open('rb') as src:
                    while chunk := src.read(1024 * 1024):
                        dest.write(chunk)
                        digest.update(chunk)
                        total.update(chunk)
                        part_size += len(chunk)
                if digest.hexdigest() != entry['sha256'] or part_size != entry['bytes']:
                    raise ValueError('A backup part is missing or corrupted.')
                size += part_size
        if total.hexdigest() != manifest['encryptedSha256'] or size != manifest['encryptedBytes']:
            raise ValueError('Combined backup checksum mismatch.')
        decrypt(joined, key_file, output)
    finally:
        if joined is not None:
            joined.unlink(missing_ok=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--key-file', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    decrypt(args.archive, args.key_file, args.output)
    print('Backup authenticated and decrypted. The ZIP contains BACKUP-MANIFEST.json.')

if __name__ == '__main__':
    main()
