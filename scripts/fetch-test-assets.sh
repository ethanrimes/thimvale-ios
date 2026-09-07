#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Vendor
if [ ! -f Vendor/smoke-model.gguf ]; then
  curl --fail --location --retry 3 https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/cdf97bd8205908758f44aec508d68ac1aef98f5c/LFM2.5-230M-Q4_K_M.gguf -o Vendor/smoke-model.gguf
fi
printf '%s\n' '7bbd90384d3deffe4c646ec9643b212802d32d4ce417c90a1ec9282100650062  Vendor/smoke-model.gguf' | shasum -a 256 -c -
if [ ! -f Vendor/smoke-wikipedia.zim ]; then
  curl --fail --location --retry 3 https://download.kiwix.org/zim/wikipedia/wikipedia_en_knots_maxi_2026-07.zim -o Vendor/smoke-wikipedia.zim
fi
printf '%s\n' '26a926e463151a796ac4ba3274011b51da6967860c5edd8cf22ffc5edafbfeba  Vendor/smoke-wikipedia.zim' | shasum -a 256 -c -
