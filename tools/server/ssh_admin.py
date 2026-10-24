"""Run a reviewed Python maintenance script over the configured SSH connection."""
import argparse
from pathlib import Path
import subprocess
import sys

HOST = "opc@138.2.185.151"
SSH = "C:/Windows/System32/OpenSSH/ssh.exe"
KEY = Path("C:/Users/mkund/Downloads/ssh-key-2026-10-24.key")

def execute(script, *, timeout=1200):
    return subprocess.run(
        [SSH, "-i", str(KEY), "-o", "BatchMode=yes",
         "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=20",
         "-o", "ServerAliveCountMax=3", HOST, "python3 -"],
        input=script, text=True, encoding="utf-8", timeout=timeout,
        check=True,
    )

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("script", type=Path)
    options = parser.parse_args()
    execute(options.script.read_text(encoding="utf-8"))
