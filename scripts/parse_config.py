#!/usr/bin/env python3
"""Parse local config.toml (if present) and build metadata into mobile/dart_defines.json."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib


def read_pubspec_version(repo_root: Path) -> str:
    pubspec = repo_root / "mobile" / "pubspec.yaml"
    if not pubspec.exists():
        return "1.0.0"
    for line in pubspec.read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip().split("+", 1)[0]
    return "1.0.0"


def read_git_sha(repo_root: Path) -> str:
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=repo_root,
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return out
    except Exception:
        return ""


def read_build_date(repo_root: Path) -> str:
    try:
        out = subprocess.check_output(
            ["git", "log", "-1", "--format=%cI"],
            cwd=repo_root,
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if out:
            dt = datetime.fromisoformat(out).astimezone(timezone.utc)
            return dt.strftime("%Y-%m-%d %H:%M UTC")
    except Exception:
        pass
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    config_path = repo_root / "config.toml"
    out_path = repo_root / "mobile" / "dart_defines.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    smb: dict[str, object] = {}
    whatsapp: dict[str, object] = {}
    telegram: dict[str, object] = {}
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
        wa_section = data.get("whatsapp", {})
        if isinstance(wa_section, dict):
            whatsapp = wa_section
        tg_section = data.get("telegram", {})
        if isinstance(tg_section, dict):
            telegram = tg_section
        print(f"Loaded compile-time defaults from {config_path}")
    else:
        print(
            f"Note: {config_path} not found; writing empty compile-time defaults "
            f"(copy config.example.toml -> config.toml to inject NAS defaults)."
        )

    whatsapp_key = os.environ.get("UBACK_WHATSAPP_KEY_OVERRIDE")
    if whatsapp_key is None:
        whatsapp_key = str(whatsapp.get("backup_key_64", ""))
    else:
        whatsapp_key = whatsapp_key.strip()

    defines = {
        "UBACK_DESTINATION_TYPE": destination_type,
        "UBACK_SMB_HOST": str(smb.get("host", "")),
        "UBACK_SMB_PORT": str(smb.get("port", 445)),
        "UBACK_SMB_SHARE": str(smb.get("share", "")),
        "UBACK_SMB_BASE_PATH": str(smb.get("base_path", "")),
        "UBACK_SMB_USERNAME": str(smb.get("username", "")),
        "UBACK_SMB_PASSWORD": str(smb.get("password", "")),
        "UBACK_SMB_DOMAIN": str(smb.get("domain", "")),
        "UBACK_WHATSAPP_KEY": whatsapp_key,
        "UBACK_ENABLE_TELEGRAM": "true" if bool(telegram.get("enabled", True)) else "false",
        "UBACK_TELEGRAM_API_ID": str(telegram.get("api_id", "")),
        "UBACK_TELEGRAM_API_HASH": str(telegram.get("api_hash", "")),
        "UBACK_TELEGRAM_PHONE": str(telegram.get("phone_number", "")),
        "UBACK_TELEGRAM_PASSWORD": str(telegram.get("password", "")),
        "UBACK_APP_VERSION": read_pubspec_version(repo_root),
        "UBACK_BUILD_DATE": read_build_date(repo_root),
        "UBACK_GIT_SHA": read_git_sha(repo_root),
    }

    with out_path.open("w", encoding="utf-8") as f:
        json.dump(defines, f, indent=2)
        f.write("\n")

    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
