#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Pass a simulator UUID when more than one is booted. Never launch by display name.
thimvale_device="${1:-booted}"
xcrun simctl bootstatus "$thimvale_device" -b
xcodebuild -project Thimvale.xcodeproj -scheme Thimvale \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$thimvale_device" build/Build/Products/Debug-iphonesimulator/Thimvale.app
xcrun simctl launch --terminate-running-process "$thimvale_device" com.ethanrimes.thimvale
echo 'Launched Thimvale (com.ethanrimes.thimvale). No JavaScript server is needed.'
