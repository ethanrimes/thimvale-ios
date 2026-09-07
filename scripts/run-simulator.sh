#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Pass a simulator UUID when more than one is booted. Never launch by display name.
pocketmind_device="${1:-booted}"
xcrun simctl bootstatus "$pocketmind_device" -b
xcodebuild -project PocketMind.xcodeproj -scheme PocketMind \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$pocketmind_device" build/Build/Products/Debug-iphonesimulator/PocketMind.app
xcrun simctl launch --terminate-running-process "$pocketmind_device" com.ethanrimes.pocketmind
echo 'Launched PocketMind (com.ethanrimes.pocketmind). No JavaScript server is needed.'
