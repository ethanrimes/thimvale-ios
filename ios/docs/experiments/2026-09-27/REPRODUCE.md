# Cross-app simulator study

These harnesses call the apps' actual inference adapters inside Release simulator builds. They do not time normal chat rendering, document retrieval, tool execution, image encoding, or App Store binaries. The patches are test instrumentation, not changes proposed for the competitors' shipping apps.

## Fixed inputs

Use `ios/Tests/Fixtures/cross-app-study.json`. The user message is identical across apps; raw prompts for competitors are expanded from each GGUF's chat template, with Qwen thinking disabled to match Thimvale. The reporter rejects differing prompt token counts, incomplete repetitions, and unmatched output/callback counts. LLMFarm exposes per-token callbacks rather than an independent native generation counter; its harness stops at 128 callbacks. The inspected pinned wrapper calls back once per non-skipped sampled token (including an empty fragment for incomplete UTF-8). This English-text workload does not establish validity for arbitrary Unicode or special-token-heavy output.

Six CPU generation threads, 4,096 context tokens, temperature zero, and 128 output tokens. Reload a fresh context for each repetition. Repetition -1 is an excluded warmup; repetitions 0–3 are measured. These are warm-OS-file-cache model reloads, not a cold disk benchmark. Throughput is 127 token intervals divided by first-to-last streaming-callback time. Load time and request-to-first-callback time are separate.

Thimvale applies its built-in repeat penalty of 1.1 over 64 tokens; PocketPal is explicitly configured to the same values. LLMFarm's pinned Swift wrapper does not apply its exposed repeat-penalty setting in the temperature-zero branch (it creates distribution + greedy samplers). We leave that upstream behavior unchanged, so this is an app-runtime comparison, not an identical-sampler/kernel microbenchmark. Generated wording can differ even at temperature zero. Gemma and LFM receive duplicated BOS tokens through the existing template + automatic-special-token behavior, consistently across all three adapters; their prompt counts are 244 and 229. Qwen has 234 input tokens. This study does not validate answer quality or ideal chat formatting.

Thimvale and PocketPal use 256/128 batch/microbatch sizes. LLMFarm's public wrapper evaluates input in 256-token chunks, but its bundled native context retains upstream 2,048/512 batch/microbatch defaults and its unexposed batch-thread setting. Its prefill timings are therefore not a strictly configuration-matched kernel benchmark. No competitor engine was upgraded to make a model load or to improve its speed.

| File | SHA-256 |
| --- | --- |
| `Vendor/smoke-model.gguf` — LFM2.5 230M Q4_K_M | `7bbd90384d3deffe4c646ec9643b212802d32d4ce417c90a1ec9282100650062` |
| `Vendor/experiments/qwen3-06-q8.gguf` | `9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031` |
| `Vendor/experiments/gemma3-1b-q4.gguf` | `8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135` |

Fetch with the existing `fetch-test-assets.sh` and `fetch-experiment-assets.sh` scripts. Do not compare speeds across different model/quantization rows as if they measured app overhead.

## Thimvale

Base application code: `de3ccc71afc7ab8ad56e7d30e8403c2849ee35ad`, with this change's model-picker and opt-in experiment additions. Native llama.cpp is pinned to b10830; no inference implementation was changed in this study.

```sh
cd ios
THIMVALE_SIMULATOR_ID=YOUR_DEDICATED_SIMULATOR_UUID bash scripts/run-experiments.sh cross-app
```

Use a dedicated simulator, not one running another test session. This builds Release with testability enabled, runs only `ExperimentTests/testCrossAppInference`, and writes synthetic outputs and measurements to `TestResults/cross-app-thimvale.json`. Confirm the testcase actually passed and all 15 rows exist before using that file. Normal CI skips this opt-in test. To repeat without compilation, use `xcodebuild test-without-building` with the same Release configuration, test selection, destination, derived-data directory, and `ENABLE_TESTABILITY=YES`; give each run a distinct result-bundle path and preserve the previous JSON before it is overwritten.

## PocketPal

1. Clone `https://github.com/a-ghorbani/pocketpal-ai` at `ebe1425a569c56496eda15ae3a471c84773fdb05` (1.18.0, llama.rn 0.13.0-rc.5).
2. Apply `pocketpal-study.patch`. Install dependencies with Yarn 1.22.22, using the checked-in lockfile; run `pod install` in `ios`.
3. Supply the dummy `ios/Config/Env.xcconfig`, `.env`, and `ios/GoogleService-Info.plist` described by the upstream iOS CI workflow. Disable authentication/PalsHub features and analytics for this local study; no real account/API credentials are needed.
4. Build `PocketPal.xcworkspace`, scheme `PocketPal`, configuration Release, SDK iphonesimulator, arm64, `CODE_SIGNING_ALLOWED=NO`, with `E2E_BUILD=true` in the environment. Limit build jobs to suit host memory. The E2E flag embeds the upstream automation route; no Metro server is needed at runtime.
5. Install the app on the benchmark simulator. Copy the protocol JSON to its Documents directory as `thimvale-study.json`, replacing each relative model path with the absolute path to the corresponding checksummed GGUF on this Mac. The simulator permits those host paths; this is not a physical-iPhone file-access recipe.
6. Open `pocketpal://e2e/benchmark?autostart=1`, accept the iOS Open prompt, and tap **Run benchmark matrix** if the screen remains idle (autostart did not fire on this simulator). The patched test-only Run action uses the study config and writes `Documents/study-results.json`. It does not submit results to a leaderboard. Restart the app for another run and preserve the previous report first.

The harness calls the installed `llama.rn` completion API with streaming enabled, zero GPU layers plus `devices: ['CPU']` / `no_gpu_devices: true`, F16 KV, mmap, flash attention auto (as in Thimvale's native context defaults), and a fresh context per repetition. Thimvale sets zero GPU layers in the simulator but still registers the simulator Metal backend; this is not a claim that all backend settings are identical. The older LLMFarm CPU framework retains its upstream flash-attention behavior.

The pinned `llama.rn` native `tokens_predicted` counter is **127 for 128 emitted tokens**: in `cpp/rn-completion.cpp`, `nextToken()` sets `tg` false for multi-token prefill and increments the counter only when `tg` is true, excluding the first sampled token. The reporter adds that first token only if the native counter is 127, there are exactly 128 nonempty streaming events, their concatenation matches the completed text, and the request stopped at the output limit without interruption/EOS/truncation. Raw data retains the unmodified native counters and events. It does not silently accept arbitrary counter mismatches or batched callbacks.

## LLMFarm

1. Clone `https://github.com/guinmoon/LLMFarm` at `ee6d251ab6fee083482fe1ee22f2291f4f7dfbaf` (1.6.0) with recursive submodules. Core Swift revision: `31d8d25ad6450b41a4e42e3acd1dc0dae3f1e20d`.
2. Apply `llmfarm-study.patch` in the root and `llmfarm-package.patch` inside `llmfarm_core.swift`. The package patch selects the repository's supplied CPU XCFramework rather than a missing locally built framework. The shortcut wording fix is required by Xcode 26.1.1. Neither patch modifies decoding kernels.
3. Build `LLMFarm.xcodeproj`, scheme `LLMFarm_Release`, Release, arm64 iOS Simulator, signing disabled. Install `LLMFarm.app` (`com.appledev.LLMFarmDev`).
4. Put the same resolved protocol JSON in its Documents directory, named `thimvale-study.json`.
5. Launch using `SIMCTL_CHILD_THIMVALE_STUDY=1 xcrun simctl launch --terminate-running-process SIMULATOR_ID com.appledev.LLMFarmDev`. The simulator-only harness runs the normal Swift core's `load_model` / `Predict` API on a user-initiated queue and writes `Documents/study-results.json` incrementally.

Both comparator repositories are MIT-licensed; their license notices accompany the patches. Source-build results do not certify the configuration or performance of their current App Store releases.

## Reporting

Finish all builds before timing. Run one app at a time; do not leave another inference loop running. Keep failed/unsupported models in the report, never encode them as zero tokens/sec. Preserve pilot runs separately and do not mix their timings into measured samples. Record host hardware, OS/SDK, other workload, thermal state when available, run order, and any deviations.

```sh
python3 ios/scripts/summarize-cross-app.py thimvale.json pocketpal.json llmfarm.json
```

The script prints medians and ranges from the four measured repetitions per successful app/model. It is intentionally strict: investigate mismatches instead of bypassing validation. In particular, this is a CPU simulator experiment on a Mac, not evidence of iPhone Metal throughput, battery life, sustained thermals, or accuracy.
