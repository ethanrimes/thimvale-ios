#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Vendor/minja Vendor/nlohmann
if [ ! -d Vendor/llama.cpp-b10830 ]; then
  curl --fail --location --retry 3 https://github.com/ggml-org/llama.cpp/archive/refs/tags/b10830.tar.gz -o Vendor/llama-source.tar.gz
  printf '%s\n' 'e8a4cc5bc213004e70803225559c409f3ca2e497d1a8e757079a30a03d9670a6  Vendor/llama-source.tar.gz' | shasum -a 256 -c -
  tar -xzf Vendor/llama-source.tar.gz -C Vendor
fi
for header in minja.hpp chat-template.hpp; do
  if [ ! -f "Vendor/minja/$header" ]; then
    curl --fail --location --retry 3 "https://raw.githubusercontent.com/google/minja/021c2293c187789ef13d56c6cfd89c9b134fd80f/include/minja/$header" -o "Vendor/minja/$header"
  fi
done
if [ ! -f Vendor/nlohmann/json.hpp ]; then
  curl --fail --location --retry 3 https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp -o Vendor/nlohmann/json.hpp
fi
printf '%s\n' \
  '55df85289038d54566ac40903617725e82a9e07e60a21b38dc6de65f7b7e10b8  Vendor/minja/minja.hpp' \
  '87db93c98fd215b70b6f8908f55015a696cd92564dd4fced19bb11f103d475d4  Vendor/minja/chat-template.hpp' \
  '9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6  Vendor/nlohmann/json.hpp' | shasum -a 256 -c -
