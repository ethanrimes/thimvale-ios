# Model recommendations — reviewed September 27, 2026

The iOS picker now offers six explicit use cases instead of recommending the first catalog row. The offline snapshot is in `shared/model-recommendations.json`; it is bundled with iOS and available in Android's shared assets. This change does not switch anyone's selected model or start a download.

## Selection

| Use | Model | 16K mobile score | Published iPhone 17 Pro tokens/sec |
| --- | --- | ---: | ---: |
| Balanced | LFM2.5-2.6B | 62.6 | 37.2 |
| Quick replies | LFM2.5-1.2B-Instruct | 42.5 | 84.1 |
| Small download | MiniCPM5-1B | 44.7 | 102.1 |
| Text and images | Qwen3.5 4B | 58.6 | 20.0 |
| Quality first | Nanbeige4.2-3B | 63.2 | 14.3 |
| Higher RAM | Ling 3.0 Tiny | 59.2 | 54.6 |

Source: [Artificial Analysis live mobile leaderboard](https://artificialanalysis.ai/hardware-inference-stack/mobile-phones), not its general Intelligence Index. These are published Q4_K_M / iPhone measurements, **not Thimvale measurements**. Generation uses a 1,024-token prompt and 256-token output. Quality uses the 16K evaluation track. All selected scores except LFM2.5-1.2B-Instruct use reasoning-enabled evaluation; Thimvale currently requests non-thinking responses and a 4K context. A published score is not a prediction of the app's answer accuracy. Text benchmarks do not measure image understanding.

LFM2.5-2.6B is the default recommendation on devices in approximately the 6 GB RAM class or above; the 1.2B Instruct model is the lighter default. These choices balance the published quality/speed tradeoff, not just the highest score. Nanbeige leads the reviewed 16K mobile quality table but generates more slowly. Ling's active-parameter count is not its memory footprint: all 7.9B parameters need storage. Device memory guidance remains conservative and is not an allocation guarantee.

The score combines GPQA Diamond, MATH-500, IFBench, BFCL-small, and the average of Omniscience accuracy/non-hallucination. See the [benchmark methodology](https://artificialanalysis.ai/methodology/mobile-device-benchmark-set). Do not mix these numbers with the separate general Intelligence Index, 64K track, one-minute track, or vendor-specific agent benchmarks.

## Cross-checks and other candidates

- [Liquid's LFM2.5-2.6B release](https://www.liquid.ai/blog/lfm2-5-2-6b) and [official GGUF card](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF) establish its intended on-device/tool-use role and available quantizations. Vendor evaluation is corroborating context, not an independent score substituted into the table.
- Official cards verify [MiniCPM5-1B](https://huggingface.co/openbmb/MiniCPM5-1B-GGUF), [Qwen3.5-4B vision support](https://huggingface.co/Qwen/Qwen3.5-4B), [Nanbeige4.2](https://huggingface.co/Nanbeige/Nanbeige4.2-3B), and [Ling's total versus active parameters](https://huggingface.co/inclusionAI/Ling-3.0-tiny). Qwen, Nanbeige, and Ling use community GGUF conversions in the catalog; their model cards are not a certification of those files in Thimvale.
- MiniCPM5-2B and Granite 4.2-3B remain available in the catalog. Their general-index results are not directly interchangeable with the mobile leaderboard used here. Gemma, Phi, Nemotron, and other families remain discoverable; no existing model was removed.
- The repository/quantization availability check passed for all 40 catalog entries. This verifies file availability, not successful device inference for every model. Runtime testing is narrower; see the experiment report.

The picker exposes the review date, score, reasoning mode, source links, and limitations in its expandable benchmark details. Update the shared snapshot after checking the live page and model cards; do not silently relabel old results as current. Unit tests check bundled decoding, catalog references, and memory-aware defaults.
