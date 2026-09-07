#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Vendor
if [ ! -d Vendor/build-apple/llama.xcframework ]; then
  curl --fail --location --retry 3 https://github.com/ggml-org/llama.cpp/releases/download/b10830/llama-b10830-xcframework.zip -o Vendor/llama.zip
  printf '%s\n' 'b8e1b5ff5fa7075c950f5198ca2944a1473f4053392b5e4f14a39a2ce0b3efd6  Vendor/llama.zip' | shasum -a 256 -c -
  unzip -q Vendor/llama.zip -d Vendor
fi
if [ ! -d Vendor/libkiwix_xcframework-14.2.1-2/lib/CoreKiwix.xcframework ]; then
  curl --fail --location --retry 3 https://download.kiwix.org/release/libkiwix/libkiwix_xcframework-14.2.1-2.tar.gz -o Vendor/kiwix.tar.gz
  printf '%s\n' '14820648788dddc3df8a89ff0820af60d7efc1cfda6c83602989455263ee1561  Vendor/kiwix.tar.gz' | shasum -a 256 -c -
  tar -xzf Vendor/kiwix.tar.gz -C Vendor
fi
mkdir -p Vendor/minja Vendor/nlohmann
for header in minja.hpp chat-template.hpp; do
  if [ ! -f "Vendor/minja/$header" ]; then
    curl --fail --location --retry 3 "https://raw.githubusercontent.com/google/minja/021c2293c187789ef13d56c6cfd89c9b134fd80f/include/minja/$header" -o "Vendor/minja/$header"
  fi
done
if [ ! -f Vendor/nlohmann/json.hpp ]; then
  curl --fail --location --retry 3 https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp -o Vendor/nlohmann/json.hpp
fi
if [ -f project.yml ]; then xcodegen generate; fi
