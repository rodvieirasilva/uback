#!/usr/bin/env python3
"""Verify E2E uploaded SMB files, SHA-256 hashes, Device Snapshots, and opt-in exclusion."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys


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

    leftovers = list(dest_root.rglob("*.uback.tmp"))
    if leftovers:
        raise SystemExit(f"FAIL: Leftover temp files found: {leftovers}")

    download_hits = list(dest_root.rglob("*random_download*"))
    if download_hits:
        raise SystemExit(f"FAIL: Opt-in Download file should NOT have been backed up: {download_hits}")

    print(
        f"OK: All {len(EXPECTED_RELATIVE_PATHS)} media/doc/custom files + 3 Device Snapshots "
        "(Contacts, SMS, Call Logs) verified, zero .uback.tmp leftovers, opt-in Download excluded."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
