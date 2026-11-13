"""Sunucuya kurulum veya canlı doğrulama betiği. Dosya: ssh_admin.py. Run a reviewed Python maintenance script over the configured SSH connection."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.runtime_config import ssh_host, ssh_key

SSH = shutil.which("ssh") or "ssh"

def execute(script, *, timeout=1200):
    return subprocess.run(
        [SSH, "-i", str(ssh_key()), "-o", "BatchMode=yes",
         "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=yes",
         "-o", "ServerAliveInterval=20",
         "-o", "ServerAliveCountMax=3", ssh_host(), "python3 -"],
        input=script, text=True, encoding="utf-8", timeout=timeout,
        check=True,
    )

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("script", type=Path)
    options = parser.parse_args()
    execute(options.script.read_text(encoding="utf-8"))
