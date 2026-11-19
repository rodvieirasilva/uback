#!/usr/bin/env python3
"""Parse local config.toml (if present) into mobile/dart_defines.json for Flutter builds."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import tomllib


def read_pubspec_version(repo_root: Path) -> str:
    pubspec = repo_root / "mobile" / "pubspec.yaml"
    if not pubspec.exists():
        return "1.0.0+1"
    for line in pubspec.read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip()
    return "1.0.0+1"


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    config_path = repo_root / "config.toml"
    out_path = repo_root / "mobile" / "dart_defines.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    smb: dict[str, object] = {}
    destination_type = "smb_nas"
    if config_path.exists():
        with config_path.open("rb") as f:
            data = tomllib.load(f)
        dest_section = data.get("destination", {})
        if isinstance(dest_section, dict) and dest_section.get("type"):
            destination_type = str(dest_section["type"])
        smb_section = data.get("smb", {})
        if isinstance(smb_section, dict):
            smb = smb_section
        print(f"Loaded compile-time defaults from {config_path}")
    else:
        print(
            f"Note: {config_path} not found; writing empty compile-time defaults "
            f"(copy config.example.toml -> config.toml to inject NAS defaults)."
        )

    defines = {
        "UBACK_DESTINATION_TYPE": destination_type,
        "UBACK_SMB_HOST": str(smb.get("host", "")),
        "UBACK_SMB_PORT": str(smb.get("port", 445)),
        "UBACK_SMB_SHARE": str(smb.get("share", "")),
        "UBACK_SMB_BASE_PATH": str(smb.get("base_path", "")),
        "UBACK_SMB_USERNAME": str(smb.get("username", "")),
        "UBACK_SMB_PASSWORD": str(smb.get("password", "")),
        "UBACK_SMB_DOMAIN": str(smb.get("domain", "")),
        "UBACK_APP_VERSION": read_pubspec_version(repo_root),
    }

    with out_path.open("w", encoding="utf-8") as f:
        json.dump(defines, f, indent=2)
        f.write("\n")

    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
