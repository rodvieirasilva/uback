#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AVD_NAME="${UBACK_AVD_NAME:-uback_test_avd}"
PKG="uback.rodvieirasilva.github.io"
OUT_DIR="$REPO_ROOT/docs/screenshots"
APK_PATH="$REPO_ROOT/mobile/build/app/outputs/flutter-apk/app-debug.apk"

STARTED_EMULATOR=0
EMU_PID=""
EMU_SERIAL=""
TMP_DIR="$(mktemp -d /tmp/uback-shots-XXXXXX)"

cleanup() {
  if [[ "$STARTED_EMULATOR" -eq 1 && "${KEEP_EMULATOR:-0}" != "1" ]]; then
    [[ -n "$EMU_SERIAL" ]] && adb -s "$EMU_SERIAL" emu kill >/dev/null 2>&1 || true
    [[ -n "$EMU_PID" ]] && kill -0 "$EMU_PID" 2>/dev/null && kill "$EMU_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

APP_VERSION="$(python3 -c "from pathlib import Path; import sys; sys.path.insert(0, '$REPO_ROOT/scripts'); import parse_config; print(parse_config.read_pubspec_version(Path('$REPO_ROOT')))")"
BUILD_DATE="$(python3 -c "from pathlib import Path; import sys; sys.path.insert(0, '$REPO_ROOT/scripts'); import parse_config; print(parse_config.read_build_date(Path('$REPO_ROOT')))")"
GIT_SHA="$(python3 -c "from pathlib import Path; import sys; sys.path.insert(0, '$REPO_ROOT/scripts'); import parse_config; print(parse_config.read_git_sha(Path('$REPO_ROOT')))")"

# Build APK BEFORE starting emulator so Gradle CPU load doesn't trigger System UI ANR.
if [[ "${SKIP_BUILD:-0}" != "1" || ! -f "$APK_PATH" ]]; then
  echo "==> Building screenshot APK (v$APP_VERSION • $BUILD_DATE • $GIT_SHA) with clean demo SMB defaults..."
  cd "$REPO_ROOT/mobile"
  flutter build apk --debug --target-platform=android-x64 \
    --dart-define=UBACK_SMB_HOST=192.168.1.100 \
    --dart-define=UBACK_SMB_PORT=445 \
    --dart-define=UBACK_SMB_SHARE=safe \
    --dart-define=UBACK_SMB_BASE_PATH=local/phone \
    --dart-define=UBACK_SMB_USERNAME=backup-user \
    --dart-define=UBACK_SMB_PASSWORD=demo-pass \
    --dart-define=UBACK_E2E_DEVICE_OVERRIDE=my-phone \
    --dart-define=UBACK_APP_VERSION="$APP_VERSION" \
    --dart-define=UBACK_BUILD_DATE="$BUILD_DATE" \
    --dart-define=UBACK_GIT_SHA="$GIT_SHA"
fi

EMU_SERIAL="$(adb devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ {print $1; exit}')"
if [[ -z "$EMU_SERIAL" ]]; then
  bash "$REPO_ROOT/scripts/ensure_avd.sh"
  echo "==> Starting headless Android Emulator ($AVD_NAME) for screenshots..."
  emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim \
    -gpu swiftshader_indirect -no-snapshot-save >"$TMP_DIR/emulator.log" 2>&1 &
  EMU_PID=$!
  STARTED_EMULATOR=1
  for _ in $(seq 1 90); do
    EMU_SERIAL="$(adb devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ {print $1; exit}')"
    [[ -n "$EMU_SERIAL" ]] && break
    sleep 2
  done
fi

adb -s "$EMU_SERIAL" wait-for-device
for _ in $(seq 1 120); do
  [[ "$(adb -s "$EMU_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] && break
  sleep 2
done
adb -s "$EMU_SERIAL" shell input keyevent 82 >/dev/null 2>&1 || true
sleep 3

adb -s "$EMU_SERIAL" shell pm clear "$PKG" >/dev/null 2>&1 || true
adb -s "$EMU_SERIAL" install -r "$APK_PATH"
adb -s "$EMU_SERIAL" shell pm grant "$PKG" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
adb -s "$EMU_SERIAL" shell pm grant "$PKG" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true
adb -s "$EMU_SERIAL" shell pm grant "$PKG" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
adb -s "$EMU_SERIAL" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
adb -s "$EMU_SERIAL" shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1 || true

python3 "$REPO_ROOT/scripts/capture_screenshots.py" "$EMU_SERIAL" "$OUT_DIR"
echo "==> Screenshots updated in $OUT_DIR"
