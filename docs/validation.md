# Local validation — September 6, 2026

Environment: Apple Silicon Mac, Xcode 26.1.1, Swift 6.2.1, iPhone 17 Pro simulator running iOS 26.1. App deployment target: iOS 18.

| Check | Result |
| --- | --- |
| Swift core suite | 8 tests passed |
| Native integration suite | 9 tests passed |
| UI suite | 14 tests passed |
| Unsigned iPhone build | Passed |
| Curated Hugging Face repository validation | All 18 contain single-file GGUFs |
| Visual inspection | Chat, Models, Knowledge, and Permissions inspected; screenshots included |

The native suite uses actual external artifacts, not substitute responses:

- LiquidAI/LFM2.5-230M-GGUF, Q4_K_M, 153,406,304 bytes, revision `cdf97bd8205908758f44aec508d68ac1aef98f5c`.
- Kiwix's July 2026 English Wikipedia knots archive, 18,462,854 bytes.
- Original bowline article text retrieved through libzim and passed into the local model. The model answered with a numbered source citation.
- A real model transfer through the app's download manager, SHA-256 verification, and recovery from a completed staging file with an intentionally unusable network URL.
- File writes tested before approval, after approval, after denial, and after revoking the permission while an approval was pending. Reads remain separately permissioned; Chat cannot execute tools.

The core suite covers source numbering/deduplication, source filtering, unsupported tool syntax, corpus updates/deletion, compression, quantization, loop limits, traversal, symlinks, and overwrite refusal. Native checks also verify full-question Wikipedia retrieval and rejection of unconnected folders before approval. UI tests exercise the four tabs, filtering, Chat/Work switching, cold launch/background return, draft preservation, all import pickers, permission and settings persistence, model selection/deletion, invalid repositories, live catalogs, real local chat/history, offline source inspection, and approval/denial followed by a cited Work answer.

All 31 tests passed locally during the simulator regression pass. The combined native/UI result is `TestResults/Regression-complete.xcresult` (23 tests); the standalone core suite contributes eight. See [simulator regressions](simulator-regressions.md) for the reported red screen, reproduced bugs, and fixes. Tests use isolated storage and credentials rather than resetting the user's app.

## What these checks do not establish

No physical iPhone was connected for performance or background-transfer testing. The simulator does not provide a usable background transfer daemon in this environment, so it uses a foreground session with the same download delegate, validation, and persistence code. Physical devices use the iOS background session configuration.

No full English Wikipedia download was performed during development. Its real catalog entries, download sizes, and SHA-256 metadata are loaded by the app; actual offline search was exercised against the smaller real archive. Wikipedia uses its built-in compressed full-text index plus passage reranking, not a precomputed vector for every article.

Only the small Liquid model was exercised for inference. Availability checks for the other 17 curated entries do not prove runtime compatibility, quality, or memory fitness. Citation following and tool selection remain model-dependent; the app displays retrieved evidence and flags an answer that omits citations.

Web search's request and error paths are implemented, but no Brave API key was supplied, so a successful authenticated Brave search was not exercised. No App Store/TestFlight upload or signed device installation was performed.

Run the commands in the README to reproduce checks. Xcode test result bundles are written locally to `TestResults/` and excluded from Git.
