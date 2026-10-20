"""Decrypt a verified local backup. The recovery key must stay outside GitHub."""
import argparse
import base64
from pathlib import Path
import shutil
import tempfile
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

MAGIC = b'NHBACKUP1\0'

def decrypt(archive, key_file, output):
    archive, key_file, output = map(Path, (archive, key_file, output))
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
