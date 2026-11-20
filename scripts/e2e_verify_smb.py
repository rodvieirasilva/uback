#!/usr/bin/env python3
"""Verify E2E uploaded SMB files, SHA-256 hashes, Device Snapshots, and opt-in exclusion."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile


EXPECTED_RELATIVE_PATHS = {
    "PTT-20220501-WA0001.opus": "whatsapp/received/audios/2022/05/PTT-20220501-WA0001.opus",
    "IMG_20230110_090000.jpg": "camera/2023/01/IMG_20230110_090000.jpg",
    "invoice_2023.pdf": "whatsapp/received/documents/2023/02/invoice_2023.pdf",
    "REC_20230412_100000.m4a": "recordings/2023/04/REC_20230412_100000.m4a",
    "Screenshot_20230705_110000.png": "screenshots/2023/07/Screenshot_20230705_110000.png",
    "Screen_20230901_140000.mp4": "screen-recordings/2023/09/Screen_20230901_140000.mp4",
    "notes_2024.txt": "documents/2024/01/notes_2024.txt",
    "VID-20240201-WA0002.mp4": "whatsapp/sent/videos/2024/02/VID-20240201-WA0002.mp4",
    "VID_20240315_120000.mp4": "camera/2024/03/VID_20240315_120000.mp4",
    "drone_2024.mp4": "custom/dji-media/2024/05/drone_2024.mp4",
    "msgstore.db.crypt15": "whatsapp/databases/2024/06/msgstore.db.crypt15",
    "wa.db.crypt15": "whatsapp/backups/2024/06/wa.db.crypt15",
    "IMG-20250620-WA0003.jpg": "whatsapp/received/images/2025/06/IMG-20250620-WA0003.jpg",
}


def verify_snapshots(dest_root: Path) -> None:
    # 1. Contacts (.vcf)
    vcf_files = list((dest_root / "snapshots" / "contacts").rglob("contacts_*.vcf"))
    if not vcf_files:
        raise SystemExit(f"FAIL: Expected Contacts .vcf snapshot missing under {dest_root / 'snapshots/contacts'}")
    vcf_text = vcf_files[0].read_text(encoding="utf-8", errors="replace")
    if len(vcf_text.strip()) == 0 or "BEGIN:VCARD" not in vcf_text or "UBack Test Contact" not in vcf_text:
        raise SystemExit(f"FAIL: Contacts .vcf snapshot invalid or missing seeded contact: {vcf_files[0]}")
    print(f"OK SMB snapshot verified: {vcf_files[0].relative_to(dest_root)} ({len(vcf_text)} bytes)")

    # 2. SMS (.json)
    sms_files = list((dest_root / "snapshots" / "sms").rglob("sms_*.json"))
    if not sms_files:
        raise SystemExit(f"FAIL: Expected SMS .json snapshot missing under {dest_root / 'snapshots/sms'}")
    sms_data = json.loads(sms_files[0].read_text(encoding="utf-8"))
    if not isinstance(sms_data, list) or not any("UBack E2E SMS Payload" in str(m.get("body", "")) for m in sms_data):
        raise SystemExit(f"FAIL: SMS .json snapshot missing seeded message: {sms_files[0]}")
    print(f"OK SMB snapshot verified: {sms_files[0].relative_to(dest_root)} ({len(sms_data)} messages)")

    # 3. Call Logs (.json)
    call_files = list((dest_root / "snapshots" / "call-logs").rglob("call_logs_*.json"))
    if not call_files:
        raise SystemExit(f"FAIL: Expected Call Logs .json snapshot missing under {dest_root / 'snapshots/call-logs'}")
    call_data = json.loads(call_files[0].read_text(encoding="utf-8"))
    if not isinstance(call_data, list) or not any("5550109876" in str(c.get("number", "")) for c in call_data):
        raise SystemExit(f"FAIL: Call Logs .json snapshot missing seeded call: {call_files[0]}")
    print(f"OK SMB snapshot verified: {call_files[0].relative_to(dest_root)} ({len(call_data)} calls)")


def verify_whatsapp_sqlite_delta(dest_root: Path) -> None:
    deltas_dir = dest_root / "whatsapp" / "deltas"
    delta_files = sorted(deltas_dir.rglob("msgstore_delta_*.db"))
    if len(delta_files) != 1:
        raise SystemExit(
            f"FAIL: Expected exactly 1 incremental WhatsApp SQLite delta under {deltas_dir}, "
            f"found {len(delta_files)}: {delta_files}"
        )

    delta_db = delta_files[0]
    conn = sqlite3.connect(f"file:{delta_db}?mode=ro", uri=True)
    try:
        meta = conn.execute(
            "SELECT scope, from_row_id, to_row_id, message_count, message_table FROM delta_meta"
        ).fetchone()
        if meta != ("whatsapp", 1, 3, 3, "message"):
            raise SystemExit(f"FAIL: Unexpected delta_meta row: {meta}")

        msgs = [r[0] for r in conn.execute("SELECT text_data FROM message ORDER BY _id").fetchall()]
        expected_msgs = ["UBack E2E Message 1", "UBack E2E Message 2", "UBack E2E Message 3"]
        if msgs != expected_msgs:
            raise SystemExit(f"FAIL: Delta message rows mismatch: {msgs} != {expected_msgs}")

        chats = conn.execute("SELECT subject FROM chat").fetchall()
        jids = conn.execute("SELECT raw_string FROM jid ORDER BY _id").fetchall()
        media = conn.execute("SELECT file_path FROM message_media").fetchall()
        if not chats or chats[0][0] != "UBack E2E Chat":
            raise SystemExit(f"FAIL: Delta missing referenced chat row: {chats}")
        if len(jids) != 2:
            raise SystemExit(f"FAIL: Delta missing referenced jid rows: {jids}")
        if not media or media[0][0] != "Media/WhatsApp Images/IMG-E2E.jpg":
            raise SystemExit(f"FAIL: Delta missing referenced message_media row: {media}")
    finally:
        conn.close()

    # Also verify scripts/merge_whatsapp_deltas.py cleanly merges the delta DB
    merge_script = Path(__file__).resolve().parent / "merge_whatsapp_deltas.py"
    with tempfile.TemporaryDirectory(prefix="uback-merge-test-") as tmp:
        merged_db = Path(tmp) / "archive.db"
        subprocess.run([sys.executable, str(merge_script), str(deltas_dir), str(merged_db)], check=True)
        mconn = sqlite3.connect(f"file:{merged_db}?mode=ro", uri=True)
        try:
            merged_count = mconn.execute("SELECT COUNT(*) FROM message").fetchone()[0]
            if merged_count != 3:
                raise SystemExit(f"FAIL: Merged WhatsApp archive expected 3 messages, got {merged_count}")
        finally:
            mconn.close()

    print(
        f"OK SMB WhatsApp SQLite delta verified & merged: {delta_db.relative_to(dest_root)} "
        "(3 messages, chat/jid/media intact, 0 duplicate deltas)"
    )


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <device_smb_root> <seed_dir>", file=sys.stderr)
        return 2

    dest_root = Path(sys.argv[1])
    seed_dir = Path(sys.argv[2])

    for name, rel_path in EXPECTED_RELATIVE_PATHS.items():
        remote_path = dest_root / rel_path
        if not remote_path.exists():
            raise SystemExit(f"FAIL: Expected SMB file missing: {remote_path}")

        expected_hash = (seed_dir / f"{name}.sha256").read_text(encoding="utf-8").strip()
        actual_hash = hashlib.sha256(remote_path.read_bytes()).hexdigest()
        if actual_hash != expected_hash:
            raise SystemExit(
                f"FAIL: SHA-256 mismatch for {remote_path}: "
                f"expected {expected_hash}, got {actual_hash}"
            )
        print(f"OK SMB verified: {rel_path} (sha256={actual_hash[:16]}...)")

    verify_snapshots(dest_root)
    verify_whatsapp_sqlite_delta(dest_root)

    leftovers = list(dest_root.rglob("*.uback.tmp"))
    if leftovers:
        raise SystemExit(f"FAIL: Leftover temp files found: {leftovers}")

    download_hits = list(dest_root.rglob("*random_download*"))
    if download_hits:
        raise SystemExit(f"FAIL: Opt-in Download file should NOT have been backed up: {download_hits}")

    dup_hits = list(dest_root.rglob("*_DUP*"))
    if dup_hits:
        raise SystemExit(
            f"FAIL: Duplicate-hash file should NOT have been copied to SMB: {dup_hits}"
        )

    print(
        f"OK: All {len(EXPECTED_RELATIVE_PATHS)} unique media/doc/custom files + 3 Device Snapshots "
        "(Contacts, SMS, Call Logs) verified, duplicate-hash skipped (0 duplicate copies), "
        "zero .uback.tmp leftovers, opt-in Download excluded."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
