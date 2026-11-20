#!/usr/bin/env python3
"""Verify E2E uploaded SMB files, SHA-256 hashes, nested source layout, and opt-in exclusion."""

from __future__ import annotations

import hashlib
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

    leftovers = list(dest_root.rglob("*.uback.tmp"))
    if leftovers:
        raise SystemExit(f"FAIL: Leftover temp files found: {leftovers}")

    download_hits = list(dest_root.rglob("*random_download*"))
    if download_hits:
        raise SystemExit(f"FAIL: Opt-in Download file should NOT have been backed up: {download_hits}")

    print(
        f"OK: All {len(EXPECTED_RELATIVE_PATHS)} multi-source & custom-folder files verified, "
        "zero .uback.tmp leftovers, opt-in Download strictly excluded."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
