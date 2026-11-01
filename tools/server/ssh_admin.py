"""Run a reviewed Python maintenance script over the configured SSH connection."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

HOST = "opc@158.180.38.94"
SSH = shutil.which("ssh") or "ssh"
KEY = Path.home() / "İndirilenler" / "ssh-key-2026-10-30.key"

def execute(script, *, timeout=1200):
    return subprocess.run(
        [SSH, "-i", str(KEY), "-o", "BatchMode=yes",
         "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=yes",
         "-o", "ServerAliveInterval=20",
         "-o", "ServerAliveCountMax=3", HOST, "python3 -"],
        input=script, text=True, encoding="utf-8", timeout=timeout,
        check=True,
    )

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("script", type=Path)
    options = parser.parse_args()
    execute(options.script.read_text(encoding="utf-8"))
