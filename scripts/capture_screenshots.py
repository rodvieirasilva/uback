#!/usr/bin/env python3
"""Capture Dark and Light screenshots (Home & Settings) from a running Android Emulator."""

from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

PKG = "uback.rodvieirasilva.github.io"
ACTIVITY = f"{PKG}/.MainActivity"


def adb(serial: str, *args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(["adb", "-s", serial, *args], check=check, capture_output=True)


def screencap(serial: str, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    res = adb(serial, "exec-out", "screencap", "-p")
    out_path.write_bytes(res.stdout)
    print(f"Captured {out_path}")


def dump_ui(serial: str) -> ET.Element | None:
    res = adb(serial, "shell", "uiautomator", "dump", "/sdcard/window_dump.xml", check=False)
    if res.returncode != 0:
        return None
    xml_bytes = adb(serial, "exec-out", "cat", "/sdcard/window_dump.xml", check=False).stdout
    if not xml_bytes or not xml_bytes.lstrip().startswith(b"<"):
        return None
    try:
        return ET.fromstring(xml_bytes)
    except ET.ParseError:
        return None


def bounds_center(bounds: str) -> tuple[int, int] | None:
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    return ((x1 + x2) // 2, (y1 + y2) // 2)


def dismiss_anr_if_present(serial: str, root: ET.Element) -> bool:
    for node in root.iter("node"):
        text = node.attrib.get("text", "")
        if text in ("Wait", "Close app") and node.attrib.get("clickable") == "true":
            center = bounds_center(node.attrib.get("bounds", ""))
            if center:
                adb(serial, "shell", "input", "tap", str(center[0]), str(center[1]), check=False)
                time.sleep(1.0)
                return True
    return False


def wait_for_element(
    serial: str,
    *,
    resource_id: str | None = None,
    content_desc: str | None = None,
    text_contains: str | None = None,
    timeout_sec: float = 30.0,
) -> tuple[int, int]:
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        root = dump_ui(serial)
        if root is not None:
            if dismiss_anr_if_present(serial, root):
                continue
            for node in root.iter("node"):
                rid = node.attrib.get("resource-id", "")
                desc = node.attrib.get("content-desc", "")
                txt = node.attrib.get("text", "")
                matched = False
                if resource_id and (rid == resource_id or rid.endswith(f"/{resource_id}")):
                    matched = True
                if content_desc and (desc == content_desc or content_desc in desc):
                    matched = True
                if text_contains and (text_contains in txt or text_contains in desc):
                    matched = True
                if matched:
                    center = bounds_center(node.attrib.get("bounds", ""))
                    if center:
                        return center
        time.sleep(1.0)
    raise RuntimeError(
        f"Timed out waiting for element (resource_id={resource_id}, "
        f"content_desc={content_desc}, text_contains={text_contains})"
    )


def relaunch(serial: str, night_mode: str) -> None:
    # Clear Google Messages notifications from E2E SMS seeding and enable Do Not Disturb
    # so heads-up notification popups never overlay the AppBar in screenshots.
    adb(serial, "shell", "cmd", "notification", "set_dnd", "on", check=False)
    adb(serial, "shell", "pm", "clear", "com.google.android.apps.messaging", check=False)
    adb(serial, "shell", "cmd", "statusbar", "collapse", check=False)
    adb(serial, "shell", "cmd", "uimode", "night", night_mode, check=False)
    adb(serial, "shell", "am", "force-stop", PKG, check=False)
    time.sleep(1.0)
    adb(serial, "shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(1.5)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <emulator_serial> <output_dir>", file=sys.stderr)
        return 2

    serial = sys.argv[1]
    out_dir = Path(sys.argv[2])

    for theme_name, night_flag in (("dark", "yes"), ("light", "no")):
        relaunch(serial, night_flag)
        settings_xy = wait_for_element(
            serial,
            resource_id="open_settings_btn",
            content_desc="Settings",
            timeout_sec=35.0,
        )
        time.sleep(0.8)
        screencap(serial, out_dir / f"home-{theme_name}.png")

        for tap_attempt in range(3):
            adb(serial, "shell", "input", "tap", str(settings_xy[0]), str(settings_xy[1]))
            try:
                wait_for_element(
                    serial,
                    resource_id="settings_save_btn",
                    text_contains="SMB / NAS",
                    timeout_sec=8.0,
                )
                break
            except RuntimeError:
                if tap_attempt == 2:
                    raise
                settings_xy = wait_for_element(
                    serial,
                    resource_id="open_settings_btn",
                    content_desc="Settings",
                    timeout_sec=10.0,
                )
        time.sleep(0.8)
        screencap(serial, out_dir / f"settings-{theme_name}.png")

    adb(serial, "shell", "cmd", "uimode", "night", "yes", check=False)
    adb(serial, "shell", "cmd", "notification", "set_dnd", "off", check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
