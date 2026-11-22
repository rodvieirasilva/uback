#!/usr/bin/env python3
"""Build per-device local release APKs from WHATSAPP_64DIGI_* env vars (or ~/.credentials) + config.toml.

Strictly local helper: NEVER prints credentials/keys and writes APKs only to gitignored `dist-local/`.
Optionally pushes each built APK to `/sdcard/Download/` on a connected ADB device without installing.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import parse_config  # noqa: E402

KEY_ENV_PREFIX = "WHATSAPP_64DIGI_"
ENV_LINE_RE = re.compile(r"^(?:export\s+)?(WHATSAPP_64DIGI_[A-Za-z0-9_]+)\s*=\s*(.+)$")


def load_whatsapp_key_envs(credentials_path: Path | None) -> dict[str, str]:
    found: dict[str, str] = {}
    if credentials_path and credentials_path.exists():
        for raw_line in credentials_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            m = ENV_LINE_RE.match(line)
            if m:
                val = m.group(2).strip().strip('"').strip("'")
                if val:
                    found[m.group(1)] = val
    for k, v in os.environ.items():
        if k.startswith(KEY_ENV_PREFIX) and v.strip():
            found[k] = v.strip()
    return dict(sorted(found.items()))


def detect_adb_device(explicit_serial: str | None) -> str | None:
    if explicit_serial:
        return explicit_serial
    out = subprocess.check_output(["adb", "devices"], text=True)
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device" and not parts[0].startswith("emulator-"):
            return parts[0]
    return None


def verify_apk(apk_path: Path) -> None:
    """Verify APK zip integrity and APK Signature Scheme v2/v3 via apksigner."""
    import zipfile

    with zipfile.ZipFile(apk_path, "r") as zf:
        bad = zf.testzip()
        if bad is not None:
            raise RuntimeError(f"Corrupt zip entry in {apk_path}: {bad}")
    sdk = Path(os.environ.get("ANDROID_HOME", str(Path.home() / "Android/Sdk")))
    bt_dirs = sorted((sdk / "build-tools").glob("*")) if (sdk / "build-tools").exists() else []
    if bt_dirs:
        apksigner = bt_dirs[-1] / "apksigner"
        if apksigner.exists():
            subprocess.run([str(apksigner), "verify", str(apk_path)], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build per-device credentialed APKs from WHATSAPP_64DIGI_* env vars.")
    parser.add_argument(
        "--credentials-file",
        type=Path,
        default=Path.home() / ".credentials",
        help="Optional env file to load WHATSAPP_64DIGI_* variables from (default: ~/.credentials)",
    )
    parser.add_argument(
        "--push-downloads",
        action="store_true",
        help="Push built APKs to /sdcard/Download/ on the connected ADB phone",
    )
    parser.add_argument(
        "--install-profile",
        default=None,
        help="Optional profile tag (e.g. from WHATSAPP_64DIGI_<tag>) to also adb install -r on the connected phone",
    )
    parser.add_argument("--adb-serial", default=None, help="Optional ADB device serial")
    args = parser.parse_args()

    repo_root = SCRIPT_DIR.parent
    key_envs = load_whatsapp_key_envs(args.credentials_file)
    if not key_envs:
        print("No WHATSAPP_64DIGI_* environment variables found.", file=sys.stderr)
        return 1

    version = parse_config.read_pubspec_version(repo_root)
    dist_dir = repo_root / "dist-local"
    dist_dir.mkdir(parents=True, exist_ok=True)
    apk_src = (
        repo_root
        / "mobile"
        / "build"
        / "app"
        / "outputs"
        / "flutter-apk"
        / "app-arm64-v8a-release.apk"
    )

    need_adb = args.push_downloads or bool(args.install_profile)
    adb_serial = detect_adb_device(args.adb_serial) if need_adb else None
    if need_adb and not adb_serial:
        print("WARNING: ADB action requested, but no physical ADB device is connected.", file=sys.stderr)

    install_tag = args.install_profile.strip().lower() if args.install_profile else None
    built_apks: list[Path] = []
    for env_name, key_value in key_envs.items():
        device_tag = env_name.removeprefix(KEY_ENV_PREFIX).lower()
        print(f"==> Building v{version} release APK for profile '{device_tag}' (key from {env_name})...")

        env = os.environ.copy()
        env["UBACK_WHATSAPP_KEY_OVERRIDE"] = key_value
        env["UBACK_PROFILE"] = device_tag
        subprocess.run(
            [sys.executable, str(SCRIPT_DIR / "parse_config.py")],
            cwd=repo_root,
            env=env,
            check=True,
        )
        subprocess.run(
            [
                "flutter",
                "build",
                "apk",
                "--release",
                "--split-per-abi",
                "--target-platform=android-arm64",
                "--dart-define-from-file=dart_defines.json",
            ],
            cwd=repo_root / "mobile",
            env=env,
            check=True,
        )

        out_apk = dist_dir / f"uback-v{version}-{device_tag}.apk"
        shutil.copy2(apk_src, out_apk)
        verify_apk(out_apk)
        built_apks.append(out_apk)
        print(f"Saved & verified {out_apk} ({out_apk.stat().st_size / (1024 * 1024):.1f} MB)")

        if adb_serial and args.push_downloads:
            remote = f"/sdcard/Download/{out_apk.name}"
            subprocess.run(["adb", "-s", adb_serial, "push", str(out_apk), remote], check=True)
            print(f"Pushed to phone: {remote}")

        if adb_serial and install_tag and device_tag == install_tag:
            print(f"==> Installing {out_apk.name} onto {adb_serial}...")
            subprocess.run(["adb", "-s", adb_serial, "install", "-r", str(out_apk)], check=True)
            print(f"Installed {out_apk.name} on {adb_serial}")

    # Restore clean default dart_defines.json without any device-specific WhatsApp key override
    subprocess.run([sys.executable, str(SCRIPT_DIR / "parse_config.py")], cwd=repo_root, check=True)
    print(f"==> Built {len(built_apks)} per-device APK(s) in {dist_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
