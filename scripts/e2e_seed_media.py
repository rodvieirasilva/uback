#!/usr/bin/env python3
"""Generate deterministic synthetic JPEG, PNG, and MP4 test media for Emulator E2E tests."""

from __future__ import annotations

import hashlib
from pathlib import Path
import struct
import sys
import zlib


def make_minimal_png(tag: bytes, extra_kb: int = 4) -> bytes:
    sig = b"\x89PNG\r\n\x1a\n"

    def chunk(ctype: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(ctype + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + ctype + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    idat = zlib.compress(b"\x00\xff\x00\x00")
    text = b"Comment\x00" + tag + (b"X" * (extra_kb * 1024))
    return sig + chunk(b"IHDR", ihdr) + chunk(b"tEXt", text) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def make_minimal_jpeg(tag: bytes, extra_kb: int = 8) -> bytes:
    payload = tag + (b"J" * (extra_kb * 1024))
    com_len = min(len(payload) + 2, 65000)
    com = b"\xff\xfe" + struct.pack(">H", com_len) + payload[: com_len - 2]
    minimal_1x1 = bytes.fromhex(
        "ffd8ffe000104a46494600010101004800480000"
        "ffdb0043000302020302020303030304030304050805050404050a070706080c0a0c0c0b0a0b0b0d0e12100d0e110e0b0b1016101113141515150c0f171816141812141514"
        "ffc0000b080001000101011100"
        "ffc40014000100000000000000000000000000000009"
        "ffc40014100100000000000000000000000000000000"
        "ffda0008010100003f00d2cf20ffd9"
    )
    return minimal_1x1[:2] + com + minimal_1x1[2:]


def make_minimal_mp4(tag: bytes, extra_kb: int = 256) -> bytes:
    ftyp_body = b"isom\x00\x00\x02\x00isomiso2mp41"
    ftyp = struct.pack(">I", len(ftyp_body) + 8) + b"ftyp" + ftyp_body
    free_body = tag + (b"V" * (extra_kb * 1024))
    free_box = struct.pack(">I", len(free_body) + 8) + b"free" + free_body
    return ftyp + free_box


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(f"Usage: {sys.argv[0]} <seed_dir> [--big-file]", file=sys.stderr)
        return 2

    seed_dir = Path(sys.argv[1])
    big_mode = len(sys.argv) == 3 and sys.argv[2] == "--big-file"
    seed_dir.mkdir(parents=True, exist_ok=True)

    video_kb = 4096 if big_mode else 256
    files = {
        "IMG_20230110_090000.jpg": make_minimal_jpeg(b"oldest-cam-1", 12),
        "Screenshot_20230705_110000.png": make_minimal_png(b"oldest-ss-2", 16),
        "VID_20240315_120000.mp4": make_minimal_mp4(b"oldest-vid-3", video_kb),
        "IMG_20250620_180000.jpg": make_minimal_jpeg(b"newest-cam-4", 20),
        "IMG-20220101-WA0001.jpg": make_minimal_jpeg(b"ignored-whatsapp", 10),
    }

    for name, content in files.items():
        target = seed_dir / name
        target.write_bytes(content)
        digest = hashlib.sha256(content).hexdigest()
        (seed_dir / f"{name}.sha256").write_text(digest, encoding="utf-8")
        print(f"Seeded {name} ({len(content)} bytes, sha256={digest[:16]}...)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
