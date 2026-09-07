#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
THIMVALE_ADB="${ANDROID_HOME:?Set ANDROID_HOME}/platform-tools/adb"
THIMVALE_SERIAL="${1:?Pass the emulator serial from adb devices}"
../ios/scripts/fetch-test-assets.sh
# This debug package is separate from the production app. No user state is cleared.
"$THIMVALE_ADB" -s "$THIMVALE_SERIAL" shell mkdir -p /sdcard/Android/data/com.ethanrimes.thimvale.debug/files/fixtures
"$THIMVALE_ADB" -s "$THIMVALE_SERIAL" push ../ios/Vendor/smoke-model.gguf /sdcard/Android/data/com.ethanrimes.thimvale.debug/files/fixtures/smoke-model.gguf
"$THIMVALE_ADB" -s "$THIMVALE_SERIAL" push ../ios/Vendor/smoke-wikipedia.zim /sdcard/Android/data/com.ethanrimes.thimvale.debug/files/fixtures/smoke-wikipedia.zim
