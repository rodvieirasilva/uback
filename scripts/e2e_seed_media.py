#!/usr/bin/env python3
"""Generate deterministic synthetic JPEG, PNG, MP4, OPUS, and M4A test media for Emulator E2E tests."""

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


def make_minimal_m4a(tag: bytes, extra_kb: int = 16) -> bytes:
    ftyp_body = b"M4A \x00\x00\x00\x00M4A mp42isom"
    ftyp = struct.pack(">I", len(ftyp_body) + 8) + b"ftyp" + ftyp_body
    free_body = tag + (b"A" * (extra_kb * 1024))
    free_box = struct.pack(">I", len(free_body) + 8) + b"free" + free_body
    return ftyp + free_box


def make_minimal_opus(tag: bytes, extra_kb: int = 10) -> bytes:
    # OggS header + OpusHead payload
    header = b"OggS\x00\x02" + (b"\x00" * 20) + b"\x01\x13OpusHead\x01\x01\x38\x01\x80\xbb\x00\x00\x00\x00\x00"
    return header + tag + (b"O" * (extra_kb * 1024))


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(f"Usage: {sys.argv[0]} <seed_dir> [--big-file]", file=sys.stderr)
        return 2

    seed_dir = Path(sys.argv[1])
    big_mode = len(sys.argv) == 3 and sys.argv[2] == "--big-file"
    seed_dir.mkdir(parents=True, exist_ok=True)

    video_kb = 4096 if big_mode else 256
    files = {
        # Global oldest -> newest across ALL enabled sources:
        "PTT-20220501-WA0001.opus": make_minimal_opus(b"oldest-wa-voice-1", 10),
        "IMG_20230110_090000.jpg": make_minimal_jpeg(b"oldest-cam-img-2", 12),
        "REC_20230412_100000.m4a": make_minimal_m4a(b"oldest-recording-3", 14),
        "Screenshot_20230705_110000.png": make_minimal_png(b"oldest-ss-4", 16),
        "VID-20240201-WA0002.mp4": make_minimal_mp4(b"oldest-wa-sent-vid-5", 32),
        "VID_20240315_120000.mp4": make_minimal_mp4(b"oldest-cam-vid-6", video_kb),
        "IMG-20250620-WA0003.jpg": make_minimal_jpeg(b"newest-wa-recv-img-7", 20),
        # Untracked folder (Download) — MUST NOT be backed up or deleted
        "random_download.jpg": make_minimal_jpeg(b"ignored-download", 10),
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
