#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AVD_NAME="${UBACK_AVD_NAME:-uback_test_avd}"
SMB_PORT="${UBACK_E2E_SMB_PORT:-4455}"
CHAOS_MODE="${UBACK_E2E_CHAOS:-0}"
BACKEND_SMB_PORT="$SMB_PORT"
if [[ "$CHAOS_MODE" == "1" ]]; then
  BACKEND_SMB_PORT="$((SMB_PORT + 1))"
fi
SMB_USER="testuser"
SMB_PASS="testpass"
SMB_SHARE="safe"
SMB_BASE_PATH="local/phone"
PKG="uback.rodvieirasilva.github.io"

STARTED_EMULATOR=0
EMU_PID=""
SMB_PID=""
PROXY_PID=""
EMU_SERIAL=""
TMP_DIR="$(mktemp -d /tmp/uback-e2e-XXXXXX)"
SMB_ROOT="$TMP_DIR/smb_share"
SEED_DIR="$TMP_DIR/seed"
mkdir -p "$SMB_ROOT/$SMB_BASE_PATH" "$SEED_DIR"

cleanup() {
  local exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo "==> E2E failed (exit $exit_code). Diagnostics:" >&2
    if [[ -n "$EMU_SERIAL" ]]; then
      echo "--- logcat (UBack) ---" >&2
      adb -s "$EMU_SERIAL" logcat -d -s UBack:V AndroidRuntime:E 2>/dev/null | tail -n 60 >&2 || true
    fi
    if [[ -f "$TMP_DIR/smbserver.log" ]]; then
      echo "--- smbserver.log ---" >&2
      tail -n 40 "$TMP_DIR/smbserver.log" >&2 || true
    fi
  fi
  echo "==> Cleaning up E2E resources..."
  if [[ -n "$PROXY_PID" ]] && kill -0 "$PROXY_PID" 2>/dev/null; then
    kill "$PROXY_PID" 2>/dev/null || true
    wait "$PROXY_PID" 2>/dev/null || true
  fi
  if [[ -n "$SMB_PID" ]] && kill -0 "$SMB_PID" 2>/dev/null; then
    kill "$SMB_PID" 2>/dev/null || true
    wait "$SMB_PID" 2>/dev/null || true
  fi
  if [[ "$STARTED_EMULATOR" -eq 1 && "${KEEP_EMULATOR:-0}" != "1" ]]; then
    if [[ -n "$EMU_SERIAL" ]]; then
      adb -s "$EMU_SERIAL" emu kill >/dev/null 2>&1 || true
    fi
    if [[ -n "$EMU_PID" ]] && kill -0 "$EMU_PID" 2>/dev/null; then
      kill "$EMU_PID" 2>/dev/null || true
    fi
  fi
  rm -rf "$TMP_DIR"
  exit "$exit_code"
}
trap cleanup EXIT

ensure_emulator() {
  bash "$REPO_ROOT/scripts/ensure_avd.sh"
  EMU_SERIAL="$(adb devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ {print $1; exit}')"
  if [[ -z "$EMU_SERIAL" ]]; then
    echo "==> Starting headless Android Emulator ($AVD_NAME)..."
    emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim \
      -gpu swiftshader_indirect -no-snapshot-save >"$TMP_DIR/emulator.log" 2>&1 &
    EMU_PID=$!
    STARTED_EMULATOR=1

    for _ in $(seq 1 90); do
      EMU_SERIAL="$(adb devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ {print $1; exit}')"
      [[ -n "$EMU_SERIAL" ]] && break
      sleep 2
    done
    if [[ -z "$EMU_SERIAL" ]]; then
      echo "ERROR: Emulator did not come online:" >&2
      tail -n 40 "$TMP_DIR/emulator.log" >&2
      exit 1
    fi
  fi

  adb -s "$EMU_SERIAL" wait-for-device
  for _ in $(seq 1 120); do
    [[ "$(adb -s "$EMU_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] && break
    sleep 2
  done
  adb -s "$EMU_SERIAL" shell input keyevent 82 >/dev/null 2>&1 || true

  # Wait until Android FUSE /storage/emulated/0 storage is fully mounted and writable
  for _ in $(seq 1 60); do
    if adb -s "$EMU_SERIAL" shell "mkdir -p /sdcard/DCIM/Camera && touch /sdcard/DCIM/Camera/.uback_ready && rm -f /sdcard/DCIM/Camera/.uback_ready" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  echo "==> Emulator $EMU_SERIAL ready."
}

start_smb_server() {
  echo "==> Starting local SMB2 server on 0.0.0.0:$BACKEND_SMB_PORT..."
  PYTHONUNBUFFERED=1 uvx --from impacket smbserver.py -smb2support -debug -ip 0.0.0.0 -port "$BACKEND_SMB_PORT" \
    -username "$SMB_USER" -password "$SMB_PASS" "$SMB_SHARE" "$SMB_ROOT" \
    >"$TMP_DIR/smbserver.log" 2>&1 &
  SMB_PID=$!

  for _ in $(seq 1 30); do
    if python3 -c "import socket; s=socket.create_connection(('127.0.0.1', $BACKEND_SMB_PORT), 0.5); s.close()" 2>/dev/null; then
      break
    fi
    sleep 0.5
  done

  if [[ "$CHAOS_MODE" == "1" ]]; then
    echo "==> Starting Chaos TCP proxy on 0.0.0.0:$SMB_PORT -> 127.0.0.1:$BACKEND_SMB_PORT (slow + mid-transfer disconnect)..."
    PYTHONUNBUFFERED=1 python3 "$REPO_ROOT/scripts/smb_chaos_proxy.py" \
      --listen-port "$SMB_PORT" \
      --target-port "$BACKEND_SMB_PORT" \
      --delay-ms 8 \
      --drop-after-bytes 524288 \
      --drop-count 1 \
      >"$TMP_DIR/chaos_proxy.log" 2>&1 &
    PROXY_PID=$!
    for _ in $(seq 1 30); do
      if python3 -c "import socket; s=socket.create_connection(('127.0.0.1', $SMB_PORT), 0.5); s.close()" 2>/dev/null; then
        return 0
      fi
      sleep 0.5
    done
    echo "ERROR: Chaos proxy failed to bind port $SMB_PORT" >&2
    exit 1
  fi
}

seed_emulator_media() {
  if [[ "$CHAOS_MODE" == "1" ]]; then
    python3 "$REPO_ROOT/scripts/e2e_seed_media.py" "$SEED_DIR" --big-file
  else
    python3 "$REPO_ROOT/scripts/e2e_seed_media.py" "$SEED_DIR"
  fi

  local WA_MEDIA="/sdcard/Android/media/com.whatsapp/WhatsApp/Media"
  adb -s "$EMU_SERIAL" shell "rm -rf /sdcard/DCIM/Camera/* /sdcard/DCIM/Screenshots/* /sdcard/Pictures/Screenshots/* '/sdcard/Pictures/WhatsApp Images/'* '$WA_MEDIA' /sdcard/Recordings/* /sdcard/Download/random_download.jpg && mkdir -p /sdcard/DCIM/Camera /sdcard/Pictures/Screenshots '$WA_MEDIA/WhatsApp Images' '$WA_MEDIA/WhatsApp Video/Sent' '$WA_MEDIA/WhatsApp Voice Notes/202218' '/sdcard/Recordings/Voice Recorder' /sdcard/Download"

  # Place .nomedia inside WhatsApp Sent and Voice Notes just like real WhatsApp does on Android!
  adb -s "$EMU_SERIAL" shell "touch '$WA_MEDIA/WhatsApp Video/Sent/.nomedia' '$WA_MEDIA/WhatsApp Voice Notes/.nomedia'"

  adb -s "$EMU_SERIAL" push "$SEED_DIR/PTT-20220501-WA0001.opus" "$WA_MEDIA/WhatsApp Voice Notes/202218/PTT-20220501-WA0001.opus" >/dev/null
  adb -s "$EMU_SERIAL" push "$SEED_DIR/IMG_20230110_090000.jpg" "/sdcard/DCIM/Camera/IMG_20230110_090000.jpg" >/dev/null
  adb -s "$EMU_SERIAL" push "$SEED_DIR/REC_20230412_100000.m4a" "/sdcard/Recordings/Voice Recorder/REC_20230412_100000.m4a" >/dev/null
  adb -s "$EMU_SERIAL" push "$SEED_DIR/Screenshot_20230705_110000.png" "/sdcard/Pictures/Screenshots/Screenshot_20230705_110000.png" >/dev/null
  adb -s "$EMU_SERIAL" push "$SEED_DIR/VID-20240201-WA0002.mp4" "$WA_MEDIA/WhatsApp Video/Sent/VID-20240201-WA0002.mp4" >/dev/null
  adb -s "$EMU_SERIAL" push "$SEED_DIR/VID_20240315_120000.mp4" "/sdcard/DCIM/Camera/VID_20240315_120000.mp4" >/dev/null
  adb -s "$EMU_SERIAL" push "$SEED_DIR/IMG-20250620-WA0003.jpg" "$WA_MEDIA/WhatsApp Images/IMG-20250620-WA0003.jpg" >/dev/null
  adb -s "$EMU_SERIAL" push "$SEED_DIR/random_download.jpg" "/sdcard/Download/random_download.jpg" >/dev/null

  adb -s "$EMU_SERIAL" shell "touch -t 202205010800.00 '$WA_MEDIA/WhatsApp Voice Notes/202218/PTT-20220501-WA0001.opus'"
  adb -s "$EMU_SERIAL" shell "touch -t 202301100900.00 /sdcard/DCIM/Camera/IMG_20230110_090000.jpg"
  adb -s "$EMU_SERIAL" shell "touch -t 202304121000.00 '/sdcard/Recordings/Voice Recorder/REC_20230412_100000.m4a'"
  adb -s "$EMU_SERIAL" shell "touch -t 202307051100.00 /sdcard/Pictures/Screenshots/Screenshot_20230705_110000.png"
  adb -s "$EMU_SERIAL" shell "touch -t 202402011130.00 '$WA_MEDIA/WhatsApp Video/Sent/VID-20240201-WA0002.mp4'"
  adb -s "$EMU_SERIAL" shell "touch -t 202403151200.00 /sdcard/DCIM/Camera/VID_20240315_120000.mp4"
  adb -s "$EMU_SERIAL" shell "touch -t 202506201800.00 '$WA_MEDIA/WhatsApp Images/IMG-20250620-WA0003.jpg'"
  adb -s "$EMU_SERIAL" shell "touch -t 202101010800.00 /sdcard/Download/random_download.jpg"
  adb -s "$EMU_SERIAL" shell "content call --uri content://media/ --method scan_volume --arg external_primary" >/dev/null 2>&1 || true
  sleep 3
}

grant_permissions() {
  adb -s "$EMU_SERIAL" shell pm grant "$PKG" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
  adb -s "$EMU_SERIAL" shell pm grant "$PKG" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true
  adb -s "$EMU_SERIAL" shell pm grant "$PKG" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
  adb -s "$EMU_SERIAL" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  adb -s "$EMU_SERIAL" shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1 || true
}

verify_emulator_cleanup() {
  local WA_MEDIA="/sdcard/Android/media/com.whatsapp/WhatsApp/Media"
  for f in \
    "$WA_MEDIA/WhatsApp Voice Notes/202218/PTT-20220501-WA0001.opus" \
    "/sdcard/DCIM/Camera/IMG_20230110_090000.jpg" \
    "/sdcard/Recordings/Voice Recorder/REC_20230412_100000.m4a" \
    "/sdcard/Pictures/Screenshots/Screenshot_20230705_110000.png" \
    "$WA_MEDIA/WhatsApp Video/Sent/VID-20240201-WA0002.mp4" \
    "/sdcard/DCIM/Camera/VID_20240315_120000.mp4" \
    "$WA_MEDIA/WhatsApp Images/IMG-20250620-WA0003.jpg"; do
    if adb -s "$EMU_SERIAL" shell "test -e '$f'" 2>/dev/null; then
      echo "FAIL: Crop Mode did not delete local file $f" >&2
      exit 1
    fi
  done

  if ! adb -s "$EMU_SERIAL" shell "test -e '/sdcard/Download/random_download.jpg'" 2>/dev/null; then
    echo "FAIL: Untracked Download file was unexpectedly removed!" >&2
    exit 1
  fi
}

ensure_emulator
start_smb_server
seed_emulator_media

DART_DEFINES=(
  "--dart-define=UBACK_SMB_HOST=10.0.2.2"
  "--dart-define=UBACK_SMB_PORT=$SMB_PORT"
  "--dart-define=UBACK_SMB_SHARE=$SMB_SHARE"
  "--dart-define=UBACK_SMB_BASE_PATH=$SMB_BASE_PATH"
  "--dart-define=UBACK_SMB_USERNAME=$SMB_USER"
  "--dart-define=UBACK_SMB_PASSWORD=$SMB_PASS"
  "--dart-define=UBACK_SMB_DOMAIN="
  "--dart-define=UBACK_E2E_DEVICE_OVERRIDE=rodrigo"
)

cd "$REPO_ROOT/mobile"
flutter build apk --debug --target-platform=android-x64 "${DART_DEFINES[@]}"
adb -s "$EMU_SERIAL" install -r "$REPO_ROOT/mobile/build/app/outputs/flutter-apk/app-debug.apk"
grant_permissions

flutter test integration_test/app_e2e_test.dart -d "$EMU_SERIAL" "${DART_DEFINES[@]}"

python3 "$REPO_ROOT/scripts/e2e_verify_smb.py" "$SMB_ROOT/$SMB_BASE_PATH/rodrigo" "$SEED_DIR"
verify_emulator_cleanup

echo "==> ALL E2E EMULATOR INTEGRATION CHECKS PASSED!"
