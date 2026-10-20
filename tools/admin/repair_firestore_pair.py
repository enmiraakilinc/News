from __future__ import annotations

import argparse
import json
from pathlib import Path

import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request

from firebase_config import PROJECT_ID, admin_key_path
BASE_URL = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"
DEFAULT_COUPLE_ID = "2fBqZ0rZLBuoDA6BfDgg"
DEFAULT_STALE_UID = "TZwEmFvScheExpgpajlgNxeu1eJ2"


def get_credentials(key_path: str):
    creds = service_account.Credentials.from_service_account_file(
        key_path,
        scopes=["https://www.googleapis.com/auth/datastore"],
    )
    creds.refresh(Request())
    return creds


def read_members(doc: dict) -> list[str]:
    fields = doc.get("fields", {})
    members = fields.get("members", {})
    values = members.get("arrayValue", {}).get("values", [])
    return [v.get("stringValue") for v in values if v.get("stringValue")]


def patch_members(key_path: str, couple_id: str, stale_uid: str, dry_run: bool = False):
    creds = get_credentials(key_path)
    headers = {
        "Authorization": f"Bearer {creds.token}",
        "Content-Type": "application/json",
    }
    url = f"{BASE_URL}/couples/{couple_id}"
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    doc = resp.json()
    current_members = read_members(doc)
    filtered = [m for m in current_members if m and m != stale_uid]

    print(f"Current members: {current_members}")
    print(f"Stale UID to remove: {stale_uid}")
    print(f"Members after cleanup: {filtered}")

    if dry_run:
        print("Dry run only; no Firestore change applied.")
        return filtered

    payload = {
        "fields": {
            "members": {
                "arrayValue": {
                    "values": [{"stringValue": member} for member in filtered]
                }
            }
        }
    }
    patch_url = f"{url}?updateMask.fieldPaths=members"
    patch = requests.patch(patch_url, headers=headers, json=payload, timeout=30)
    print(f"PATCH status: {patch.status_code}")
    print(patch.text[:2000])
    patch.raise_for_status()
    print("Firestore members updated successfully.")
    return filtered


def main():
    parser = argparse.ArgumentParser(description="Remove legacy stale UID from the Neural Haber couple document.")
    parser.add_argument("--key", default=str(admin_key_path()))
    parser.add_argument("--couple-id", default=DEFAULT_COUPLE_ID)
    parser.add_argument("--stale-uid", default=DEFAULT_STALE_UID)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    patch_members(args.key, args.couple_id, args.stale_uid, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
