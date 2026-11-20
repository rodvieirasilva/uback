#!/usr/bin/env python3
"""Merge incremental UBack WhatsApp SQLite delta files (`msgstore_delta_*.db`) into one unified archive DB."""

from __future__ import annotations

import argparse
from pathlib import Path
import sqlite3
import sys


def merge_deltas(delta_dir: Path, output_db: Path) -> int:
    delta_files = sorted(delta_dir.rglob("msgstore_delta_*.db"))
    if not delta_files:
        print(f"No msgstore_delta_*.db files found under {delta_dir}", file=sys.stderr)
        return 1

    output_db.parent.mkdir(parents=True, exist_ok=True)
    dst = sqlite3.connect(output_db)
    try:
        for delta_path in delta_files:
            src = sqlite3.connect(f"file:{delta_path}?mode=ro", uri=True)
            try:
                tables = [
                    (row[0], row[1])
                    for row in src.execute(
                        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
                    ).fetchall()
                    if row[1]
                ]
                for table_name, create_sql in tables:
                    if table_name == "delta_meta":
                        continue
                    exists = dst.execute(
                        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                        (table_name,),
                    ).fetchone()
                    if not exists:
                        dst.execute(create_sql)
                    cols = [r[1] for r in src.execute(f'PRAGMA table_info("{table_name}")').fetchall()]
                    if not cols:
                        continue
                    quoted = ", ".join(f'"{c}"' for c in cols)
                    placeholders = ", ".join("?" for _ in cols)
                    rows = src.execute(f'SELECT {quoted} FROM "{table_name}"').fetchall()
                    if rows:
                        dst.executemany(
                            f'INSERT OR IGNORE INTO "{table_name}" ({quoted}) VALUES ({placeholders})',
                            rows,
                        )
                dst.commit()
                print(f"Merged {delta_path.name}")
            finally:
                src.close()
    finally:
        dst.close()

    print(f"Done! Unified archive written to {output_db}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Merge UBack WhatsApp SQLite deltas into one archive DB.")
    parser.add_argument("delta_dir", type=Path, help="Directory containing msgstore_delta_*.db files")
    parser.add_argument("output_db", type=Path, help="Output merged SQLite archive path")
    args = parser.parse_args()
    return merge_deltas(args.delta_dir, args.output_db)


if __name__ == "__main__":
    sys.exit(main())
