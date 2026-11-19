#!/usr/bin/env python3
"""Verify E2E uploaded SMB files, SHA-256 hashes, folder structure, and WhatsApp exclusion."""

from __future__ import annotations

import hashlib
from pathlib import Path
import sys


EXPECTED_RELATIVE_PATHS = {
    "IMG_20230110_090000.jpg": "camera/2023/01/IMG_20230110_090000.jpg",
    "Screenshot_20230705_110000.png": "screenshots/2023/07/Screenshot_20230705_110000.png",
    "VID_20240315_120000.mp4": "camera/2024/03/VID_20240315_120000.mp4",
    "IMG_20250620_180000.jpg": "camera/2025/06/IMG_20250620_180000.jpg",
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

    whatsapp_hits = list(dest_root.rglob("*WA0001*"))
    if whatsapp_hits:
        raise SystemExit(f"FAIL: WhatsApp file should NOT have been backed up: {whatsapp_hits}")

    print("OK: Zero .uback.tmp leftovers and WhatsApp image strictly excluded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
