#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Vendor
if [ ! -d Vendor/llama.xcframework ]; then
  curl --fail --location --retry 3 https://github.com/ggml-org/llama.cpp/releases/download/b10830/llama-b10830-xcframework.zip -o Vendor/llama.zip
  printf '%s\n' 'b8e1b5ff5fa7075c950f5198ca2944a1473f4053392b5e4f14a39a2ce0b3efd6  Vendor/llama.zip' | shasum -a 256 -c -
  unzip -q Vendor/llama.zip -d Vendor
fi
if [ ! -d Vendor/CoreKiwix.xcframework ]; then
  curl --fail --location --retry 3 https://download.kiwix.org/release/libkiwix/libkiwix_xcframework.tar.gz -o Vendor/kiwix.tar.gz
  tar -xzf Vendor/kiwix.tar.gz -C Vendor
fi
if [ -f project.yml ]; then xcodegen generate; fi
