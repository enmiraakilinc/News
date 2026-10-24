"""Send a short-lived admin read token over SSH; no credentials are persisted."""
from pathlib import Path
import json
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from google.auth.transport.requests import Request
from tools.admin.firebase_config import admin_session,PROJECT_ID
from tools.server.ssh_admin import execute
session=admin_session()
session.credentials.refresh(Request())
options={"project":PROJECT_ID,"token":session.credentials.token}
script=Path(__file__).with_name("firestore_snapshot_remote.py").read_text()
execute(script+"\nsnapshot("+repr(options)+")\n",timeout=3000)
