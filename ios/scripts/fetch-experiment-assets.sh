#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Optional, local experiment assets. Not fetched by CI and never shipped in the app.
mkdir -p Vendor/experiments
fetch() {
  local experiment_file="$1" experiment_url="$2" experiment_sha="$3"
  if [ ! -f "Vendor/experiments/$experiment_file" ]; then
    curl --fail --location --retry 3 "$experiment_url" -o "Vendor/experiments/$experiment_file.partial"
    printf '%s  %s\n' "$experiment_sha" "Vendor/experiments/$experiment_file.partial" | shasum -a 256 -c -
    mv "Vendor/experiments/$experiment_file.partial" "Vendor/experiments/$experiment_file"
  fi
  printf '%s  %s\n' "$experiment_sha" "Vendor/experiments/$experiment_file" | shasum -a 256 -c -
}
fetch qwen3-06-q8.gguf https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/23749fefcc72300e3a2ad315e1317431b06b590a/Qwen3-0.6B-Q8_0.gguf 9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031
fetch gemma3-1b-q4.gguf https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf 8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135
