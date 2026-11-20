#!/usr/bin/env python3
"""Verify Flutter/Dart line coverage meets the minimum threshold (default 80%)."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


def parse_lcov(path: Path) -> tuple[int, int, dict[str, tuple[int, int]]]:
    files: dict[str, list[int]] = {}
    current: str | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("SF:"):
            current = line[3:]
            files[current] = [0, 0]
        elif line.startswith("DA:") and current is not None:
            _, count = line[3:].split(",", 1)
            files[current][1] += 1
            if int(count) > 0:
                files[current][0] += 1
    total_hit = sum(v[0] for v in files.values())
    total_found = sum(v[1] for v in files.values())
    return total_hit, total_found, {k: (v[0], v[1]) for k, v in files.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description="Check LCOV line coverage threshold.")
    parser.add_argument(
        "lcov_path",
        nargs="?",
        default="mobile/coverage/lcov.info",
        help="Path to lcov.info (default: mobile/coverage/lcov.info)",
    )
    parser.add_argument(
        "--min",
        type=float,
        default=80.0,
        help="Minimum required coverage percentage (default: 80.0)",
    )
    args = parser.parse_args()

    lcov_file = Path(args.lcov_path)
    if not lcov_file.exists():
        print(f"ERROR: Coverage file not found: {lcov_file}", file=sys.stderr)
        return 2

    total_hit, total_found, files = parse_lcov(lcov_file)
    pct = (total_hit / total_found * 100.0) if total_found else 0.0

    print(f"Dart Line Coverage: {total_hit}/{total_found} ({pct:.1f}%) — threshold >= {args.min:.1f}%")
    for fname, (hit, found) in sorted(files.items(), key=lambda kv: (kv[1][0] / kv[1][1] if kv[1][1] else 1.0)):
        fpct = (hit / found * 100.0) if found else 100.0
        print(f"  {fpct:5.1f}% ({hit:3d}/{found:3d}) {fname}")

    if pct < args.min:
        print(f"FAIL: Coverage {pct:.1f}% is below required {args.min:.1f}%", file=sys.stderr)
        return 1

    print(f"OK: Coverage {pct:.1f}% meets >= {args.min:.1f}% requirement.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
