from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from tools.server.ssh_admin import execute
options={
 "snapshot":"/home/opc/.local/share/neural-backups/firestore-20261024T141647Z.jsonl.gz",
 "sha256":"9baca9f89ec546529a26c2b1c156aacbe1fbd78eece87966beab932574da6c8b",
 "readTime":"2026-10-24T14:16:37.755495Z",
 "schema":Path("server/sql/001_documents.sql").read_text()
}
execute(Path(__file__).with_name("import_snapshot_remote.py").read_text()+"\nimport_snapshot("+repr(options)+")\n",timeout=1200)
