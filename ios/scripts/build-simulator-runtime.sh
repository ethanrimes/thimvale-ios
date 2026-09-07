#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Official releases currently contain device and macOS slices only.
if [ ! -d Vendor/llama.cpp-b10830 ]; then
  curl --fail --location --retry 3 https://github.com/ggml-org/llama.cpp/archive/refs/tags/b10830.tar.gz -o Vendor/llama-source.tar.gz
  tar -xzf Vendor/llama-source.tar.gz -C Vendor
fi
if [ ! -d Vendor/llama.cpp-b10830/build-apple/llama.xcframework ]; then
  (cd Vendor/llama.cpp-b10830 && ./build-xcframework.sh ios-sim)
fi
if [ ! -d Vendor/llama.xcframework ]; then
  xcodebuild -create-xcframework \
    -framework Vendor/build-apple/llama.xcframework/ios-arm64/llama.framework \
    -framework Vendor/build-apple/llama.xcframework/macos-arm64_x86_64/llama.framework \
    -framework Vendor/llama.cpp-b10830/build-apple/llama.xcframework/ios-arm64_x86_64-simulator/llama.framework \
    -output Vendor/llama.xcframework
fi
