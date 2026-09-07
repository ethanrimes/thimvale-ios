# Local validation — September 6, 2026

Environment: Apple Silicon Mac, Xcode 26.1.1, Swift 6.2.1, iPhone 17 Pro simulator running iOS 26.1. App deployment target: iOS 18.

| Check | Result |
| --- | --- |
| Swift core suite | 10 tests passed |
| Native integration suite | 11 tests passed |
| UI suite | 15 tests passed |
| Release configuration suite | 9 tests passed |
| Unsigned iPhone Release archive | Passed; app identity and privacy manifest checked |
| Workflow and shell lint | Actionlint and ShellCheck passed |
| Curated Hugging Face repository validation | All 22 contain single-file GGUFs |
| Visual inspection | Chat, Models, 4B filter, Knowledge, and Permissions inspected; screenshots included |

The native suite uses actual external artifacts, not substitute responses:

- LiquidAI/LFM2.5-230M-GGUF, Q4_K_M, 153,406,304 bytes, revision `cdf97bd8205908758f44aec508d68ac1aef98f5c`.
- Kiwix's July 2026 English Wikipedia knots archive, 18,462,854 bytes.
- Original bowline article text retrieved through libzim and passed into the local model. The model answered with a numbered source citation.
- A real model transfer through the app's download manager, SHA-256 verification, and recovery from a completed staging file with an intentionally unusable network URL.
- File writes tested before approval, after approval, after denial, and after revoking the permission while an approval was pending. Reads remain separately permissioned; Chat cannot execute tools.

The core suite covers source numbering/deduplication, source filtering, unsupported tool syntax, corpus updates/deletion, compression, quantization, loop limits, traversal, symlinks, overwrite refusal, stable app identity, and 4B size classification/search. Native checks also verify full-question Wikipedia retrieval, rejection of unconnected folders before approval, the installed public name, and distinct catalog IDs with memory guidance. UI tests exercise the four tabs, family/4B filtering and search together, Chat/Work switching, cold launch/background return, draft preservation, all import pickers, permission and settings persistence, model selection/deletion, invalid repositories, live catalogs, real local chat/history, offline source inspection, and Work approval/denial. Work answers must expose their real retrieved evidence and either valid inline citations or an explicit visible warning that inline citations are missing; citations are never fabricated to satisfy the check. A separate native test requires a real model-generated numbered citation.

All 45 tests passed locally in the final 4B validation pass. The combined native/UI result is `TestResults/Thimvale-4b.xcresult` (26 passed, zero failed or skipped); the standalone core and release-configuration suites contribute ten and nine. The unsigned Release archive is `TestResults/Thimvale-4b.xcarchive`. Release tests exercise credential/profile validation, build numbering, export options, and event guards without real Apple secrets. They do not establish that a signed upload succeeds.

After the rename, SHA-256 hashes of the existing installation's conversation, download, folder, model, and permission JSON records matched their pre-rename values. The public name is Thimvale; the bundle ID, storage directory, Keychain service, and background transfer identifier intentionally retain their existing identity. See [simulator regressions](simulator-regressions.md) for the reported red screen, reproduced bugs, and fixes. Tests use isolated storage and credentials rather than resetting the user's app. Simulator test sessions use a fixed inference seed; ordinary app sessions do not.

## What these checks do not establish

No physical iPhone was connected for performance or background-transfer testing. The simulator does not provide a usable background transfer daemon in this environment, so it uses a foreground session with the same download delegate, validation, and persistence code. Physical devices use the iOS background session configuration.

No full English Wikipedia download was performed during development. Its real catalog entries, download sizes, and SHA-256 metadata are loaded by the app; actual offline search was exercised against the smaller real archive. Wikipedia uses its built-in compressed full-text index plus passage reranking, not a precomputed vector for every article.

Only the small Liquid model was exercised for inference. Availability checks for the other 21 curated entries, including the four newly added [4B models](models-4b.md), do not prove runtime compatibility, quality, or memory fitness. No 4B weights were downloaded or executed. Citation following and tool selection remain model-dependent; the app displays retrieved evidence and flags an answer that omits citations.

Web search's request and error paths are implemented, but no Brave API key was supplied, so a successful authenticated Brave search was not exercised. No App Store/TestFlight upload or signed device installation was performed.

Run the commands in the README to reproduce checks. Xcode test result bundles are written locally to `TestResults/` and excluded from Git.
