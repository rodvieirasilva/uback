#!/usr/bin/env bash
set -euo pipefail

AVD_NAME="${UBACK_AVD_NAME:-uback_test_avd}"
SYSTEM_IMAGE="system-images;android-35;google_apis;x86_64"

if ! avdmanager list avd -c | grep -qx "$AVD_NAME"; then
  echo "==> Creating AVD '$AVD_NAME' ($SYSTEM_IMAGE)..."
  echo "no" | avdmanager create avd \
    --force \
    --name "$AVD_NAME" \
    --package "$SYSTEM_IMAGE" \
    --device "pixel_6"
else
  echo "==> AVD '$AVD_NAME' already exists."
fi
