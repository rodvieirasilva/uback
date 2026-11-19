#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AVD_NAME="${UBACK_AVD_NAME:-uback_test_avd}"
CMD="${1:-status}"

find_emulator() {
  adb devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ {print $1; exit}'
}

case "$CMD" in
  start)
    bash "$REPO_ROOT/scripts/ensure_avd.sh"
    EXISTING="$(find_emulator)"
    if [[ -n "$EXISTING" ]]; then
      echo "Emulator already running: $EXISTING"
      exit 0
    fi
    echo "Starting persistent headless emulator ($AVD_NAME)..."
    setsid nohup emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim \
      -gpu swiftshader_indirect -no-snapshot-save \
      >/tmp/uback-emulator.log 2>&1 </dev/null &
    for _ in $(seq 1 90); do
      EMU="$(find_emulator)"
      if [[ -n "$EMU" ]]; then
        adb -s "$EMU" wait-for-device
        for _ in $(seq 1 90); do
          [[ "$(adb -s "$EMU" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] && break
          sleep 2
        done
        echo "Emulator ready: $EMU (will stay running until 'mise run emulator-stop')"
        exit 0
      fi
      sleep 2
    done
    echo "ERROR: Emulator failed to start. See /tmp/uback-emulator.log" >&2
    exit 1
    ;;
  stop)
    EMU="$(find_emulator)"
    if [[ -z "$EMU" ]]; then
      echo "No running emulator found."
      exit 0
    fi
    adb -s "$EMU" emu kill
    echo "Stopped emulator: $EMU"
    ;;
  status)
    EMU="$(find_emulator)"
    if [[ -n "$EMU" ]]; then
      echo "Running: $EMU"
    else
      echo "Not running"
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|status}" >&2
    exit 2
    ;;
esac
