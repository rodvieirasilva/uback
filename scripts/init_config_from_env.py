#!/usr/bin/env python3
"""Auto-discover NAS SMB parameters from ~/.credentials, ~/.smbcredentials, and ~/NAS,
write gitignored config.toml (0600), and test the SMB connection without printing secrets."""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys


def parse_kv_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        val = val.strip().strip('"').strip("'")
        values[key.strip()] = val
    return values


def parse_nas_symlink(nas_path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not nas_path.is_symlink():
        return result
    target = str(nas_path.readlink())
    for field, key in (("server", "host"), ("share", "share"), ("user", "username")):
        match = re.search(rf"{field}=([^,/]+)", target)
        if match:
            result[key] = match.group(1)
    return result


def toml_escape(val: str) -> str:
    return val.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    home = Path.home()

    creds = parse_kv_file(home / ".credentials")
    smb_creds = parse_kv_file(home / ".smbcredentials")
    gvfs = parse_nas_symlink(home / "NAS")

    host = creds.get("NAS_HOST") or gvfs.get("host") or ""
    share = (creds.get("NAS_SHARE") or gvfs.get("share") or "").strip("/\\")
    username = creds.get("NAS_USER") or smb_creds.get("username") or gvfs.get("username") or ""
    password = creds.get("NAS_PASSWORD") or smb_creds.get("password") or ""
    base_path = "safe/local/phone"
    port = 445

    if not host or not share:
        print("ERROR: Could not auto-discover NAS host/share from ~/.credentials or ~/NAS.", file=sys.stderr)
        return 1

    config_path = repo_root / "config.toml"
    content = (
        "# Auto-generated local NAS defaults (gitignored — NEVER commit)\n"
        "[smb]\n"
        f'host = "{toml_escape(host)}"\n'
        f"port = {port}\n"
        f'share = "{toml_escape(share)}"\n'
        f'base_path = "{toml_escape(base_path)}"\n'
        f'username = "{toml_escape(username)}"\n'
        f'password = "{toml_escape(password)}"\n'
        'domain = ""\n'
    )
    config_path.write_text(content, encoding="utf-8")
    os.chmod(config_path, 0o600)

    print(
        f"Wrote {config_path} (0600): host={host}, port={port}, share={share}, "
        f"base_path={base_path}, username={username}, password=<REDACTED>"
    )

    # Test real SMB2/SMB3 authentication and base_path access
    try:
        from impacket.smbconnection import SMBConnection

        conn = SMBConnection(host, host, sess_port=port, timeout=10)
        conn.login(username, password)
        tid = conn.connectTree(share)
        entries = conn.listPath(share, f"{base_path}/*")
        folders = sorted(
            e.get_longname()
            for e in entries
            if e.is_directory() and e.get_longname() not in (".", "..")
        )
        conn.disconnectTree(tid)
        conn.logoff()
        print(f"SMB connection OK -> smb://{host}:{port}/{share}/{base_path}")
        print(f"Existing device folders under {base_path}: {folders}")
    except Exception as exc:
        print(f"ERROR: SMB connection test failed: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
