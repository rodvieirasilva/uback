#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_MODE="${1:-debug}" # debug or release

# Detect first non-emulator connected ADB device (e.g., Samsung via Wireless ADB)
DEVICE_ID="${ADB_DEVICE:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" && $1 !~ /^emulator-/ {print $1; exit}')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "ERROR: No physical/wireless ADB device found." >&2
  echo "Connected devices:" >&2
  adb devices -l >&2
  exit 1
fi

echo "==> Target device: $DEVICE_ID"
python3 "$REPO_ROOT/scripts/parse_config.py"

cd "$REPO_ROOT/mobile"
if [[ "$BUILD_MODE" == "release" ]]; then
  flutter build apk --release --dart-define-from-file=dart_defines.json
  APK_PATH="$REPO_ROOT/mobile/build/app/outputs/flutter-apk/app-release.apk"
else
  flutter build apk --debug --dart-define-from-file=dart_defines.json
  APK_PATH="$REPO_ROOT/mobile/build/app/outputs/flutter-apk/app-debug.apk"
fi

echo "==> Installing $APK_PATH to $DEVICE_ID..."
adb -s "$DEVICE_ID" install -r "$APK_PATH"

echo "==> Launching UBack on $DEVICE_ID..."
adb -s "$DEVICE_ID" shell monkey -p uback.rodvieirasilva.github.io -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
echo "==> Done! UBack installed and launched on $DEVICE_ID."
