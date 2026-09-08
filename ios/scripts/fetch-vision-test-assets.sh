#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Vendor
base=https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/b9e4379657e1450d04d02eec8e345667265b0a00
if [ ! -f Vendor/vision-model.gguf ]; then
  curl --fail --location --retry 3 "$base/SmolVLM-256M-Instruct-Q8_0.gguf" -o Vendor/vision-model.gguf
fi
printf '%s\n' '2a31195d3769c0b0fd0a4906201666108834848db768af11de1d2cef7cd35e65  Vendor/vision-model.gguf' | shasum -a 256 -c -
if [ ! -f Vendor/vision-projector.gguf ]; then
  curl --fail --location --retry 3 "$base/mmproj-SmolVLM-256M-Instruct-f16.gguf" -o Vendor/vision-projector.gguf
fi
printf '%s\n' '0802360aca1748f112ea510b8ff277c65b1361c8ef30ed89b83c9c7a60d08e96  Vendor/vision-projector.gguf' | shasum -a 256 -c -
if [ "${1:-}" = "--qwen" ]; then
  base=https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/6ab461498e2023f6e3c1baea90a8f0fe38ab64d0
  if [ ! -f Vendor/vision-qwen.gguf ]; then
    curl --fail --location --retry 3 "$base/Qwen3.5-0.8B-Q4_K_M.gguf" -o Vendor/vision-qwen.gguf
  fi
  printf '%s\n' 'bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517  Vendor/vision-qwen.gguf' | shasum -a 256 -c -
  if [ ! -f Vendor/vision-qwen-projector.gguf ]; then
    curl --fail --location --retry 3 "$base/mmproj-F16.gguf" -o Vendor/vision-qwen-projector.gguf
  fi
  printf '%s\n' '56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453  Vendor/vision-qwen-projector.gguf' | shasum -a 256 -c -
fi
