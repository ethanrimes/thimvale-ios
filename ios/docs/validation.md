# Local validation — September 6, 2026

Environment: Apple Silicon Mac, Xcode 26.1.1, Swift 6.2.1, iPhone 17 Pro simulator running iOS 26.1. App deployment target: iOS 18.

## September 7: chat attachments, vision, and keyboard dismissal

[Attachment/vision behavior and limits](attachments-and-vision.md) now include a multiple-file picker, per-chat context, image inference through MTMD, and variant-specific Vision labels. The actual SmolVLM 256M and Qwen 3.5 0.8B GGUFs distinguished red from blue pixels with identical questions. The app-level SmolVLM test imported the projector, answered an image question, released memory in the background, reloaded, and answered a follow-up. Liquid answered an arrival-code question using an attached local text file with every tool denied. These small deterministic fixtures are integration checks, not general visual-reasoning or accuracy benchmarks.

Local regression coverage totals **120 distinct passing iOS checks across the full run and targeted follow-ups**: 57 native integration, 27 UI, 13 core, and 23 release-configuration tests. Seven opt-in experiment cases were skipped by the normal scheme. The full native/UI result is `build/Logs/Test/Test-Thimvale-2026.09.07_21-07-12--0700.xcresult`; its only failing case was the picker-cancellation test. All other tests passed. The additional real image-preview/chat UI case passed in `Test-Thimvale-2026.09.07_21-21-01--0700.xcresult`. Two passing picker repeats verify the corrected dismissal behavior in `Test-Thimvale-2026.09.07_21-22-37--0700.xcresult`.

Failures caught during implementation:

- The generated plist omitted `UIFileSharingEnabled`, leaving On My iPhone empty. The explicit Boolean plist input fixed this; the system-picker UI then selected two real files and previewed/removed them. A built-bundle regression now checks both document-sharing keys.
- SmolVLM's template used a Jinja filter absent from the pinned minja; the equivalent supported string method preserves its published format.
- Putting image filenames after the question distracted the tiny model. Moving the user's question after attachment context fixed both the first answer and follow-up.
- iOS 26 can remember a nested folder where no visible Cancel button exists. The accessibility tree also contains a non-interactive underlying Cancel element; tapping that is not a dismissal. The test now uses the real Cancel button when available or the system sheet's swipe-down gesture otherwise. No file/folder is selected by cancellation.

The unsigned physical-device Release build passed with the encryption-exemption Boolean unchanged and both sharing keys present. Actionlint and catalog-sync checks passed. Android's incremental `testDebugUnitTest` build passed after exporting the 40-model catalog; Android image input is not claimed. The inspected [image-chat](screenshots/chat-image.png) and [file-attachment](screenshots/chat-attachments.png) screenshots come from real simulator UI tests. No physical-device Metal, memory-pressure, thermal, or general vision accuracy validation is claimed.

## Model lifetime, live activity, and icon update

The [memory/activity change](model-session-and-activity.md) adds explicit preload and lifecycle state, ordered token streaming in Chat and every Work generation (including citation retries), and permission-checked tool event cards. The [new icon](app-icon.md) is an opaque 1024-square image; a native test also checks the primary icon compiled into the app. The device Release target builds with the original Boolean encryption exemption intact.

Tests use two clearly separate approaches: the native GGUF suite and simulator UI tests run the actual Liquid model, while `SessionAndStreamingTests` uses an explicitly scripted test double to control cancellation, idle timeout, and approval timing. No scripted engine is selected by the shipped app. The real runtime checks assert loaded-path/load-count reuse, native unload/reload, and recovery after a failed replacement, rather than inferring residency from a fast answer.

The first full local pass caught the activity container overriding individual tool-card accessibility IDs. Removing the inherited container ID restored independently addressable tool cards. Both the real Work flow and the import-picker flow subsequently passed in `TestResults/Thimvale-live-work-fixed.xcresult`.

Final checks: **73 distinct tests passed** (12 core, 18 release-configuration, 15 native integration, 11 lifecycle/streaming integration, 17 UI), plus **3 iPad smoke tests**. `TestResults/Thimvale-memory-activity-final.xcresult` contains the complete iPhone native/UI run (42 passed, zero failed/skipped). After preserving successful tool results when cancellation arrives on return, `TestResults/Thimvale-final-cancellation.xcresult` reran all 11 lifecycle/streaming tests, including the additional completed-write regression. `TestResults/Thimvale-memory-activity-ipad.xcresult` contains the three passing iPad mini A17 Pro flows: selection/deletion, live tokens/Stop/background/reload, and Work approval/streaming/evidence.

The final unsigned iPhone Release build passed. Actionlint and `git diff --check` passed. Exported iPhone/iPad screenshots were inspected, including the installed book-and-sun icon and live Chat/Work output. Updated [Chat](screenshots/chat-streaming.png) and [Work](screenshots/work-streaming.png) screenshots are included in the repo. No physical-device memory, thermal, or background GPU validation is claimed.

The earlier cloud run [34086236949](https://github.com/ethanrimes/thimvale-ios/actions/runs/34086236949) did **not** upload: the simulator gate failed before the signing job. Its Files picker appeared after the original 10-second wait, and its real Work answer/evidence arrived just after the original 120-second deadline. Exported result attachments show the completed answer and source buttons. The waits now remain bounded at 30 seconds for the system picker and 240 seconds for a Work turn; no test or permission check was removed. Retrieved citations are now visible before the answer, so the UI test waits for generation completion independently of citation-button existence.

## Earlier release baseline

| Check | Result |
| --- | --- |
| Swift core suite | 11 tests passed |
| Native integration suite | 13 tests passed in the signed cloud run |
| UI suite | 16 tests passed |
| Release configuration suite | 18 tests passed, including profile IDs, automatic versions, and Boolean encryption metadata |
| Unsigned iPhone Release archive | Passed; app identity and privacy manifest checked |
| Signed cloud archive and upload | Build 12.1 uploaded successfully; Apple processing is separate |
| Workflow and shell lint | Actionlint and ShellCheck passed |
| Curated Hugging Face repository validation | All 36 contain single-file GGUFs at their preferred quantization |
| Visual inspection | Chat, Models, 4B/Higher RAM filters, Knowledge, and Permissions inspected; screenshots included |

The native suite uses actual external artifacts, not substitute responses:

- LiquidAI/LFM2.5-230M-GGUF, Q4_K_M, 153,406,304 bytes, revision `cdf97bd8205908758f44aec508d68ac1aef98f5c`.
- Kiwix's July 2026 English Wikipedia knots archive, 18,462,854 bytes.
- Original bowline article text retrieved through libzim and passed into the local model. The model answered with a numbered source citation.
- A real model transfer through the app's download manager, SHA-256 verification, and recovery from a completed staging file with an intentionally unusable network URL.
- File writes tested before approval, after approval, after denial, and after revoking the permission while an approval was pending. Reads remain separately permissioned; Chat cannot execute tools.

The core suite covers source numbering/deduplication, source filtering, unsupported tool syntax, corpus updates/deletion, compression, quantization, loop limits, traversal, symlinks, overwrite refusal, stable app identity, and 4B size classification/search. Native checks also verify full-question Wikipedia retrieval, rejection of unconnected folders before approval, the installed public name, and distinct catalog IDs with memory guidance. UI tests exercise the four tabs, family/4B filtering and search together, Chat/Work switching, cold launch/background return, draft preservation, all import pickers, permission and settings persistence, model selection/deletion, invalid repositories, live catalogs, real local chat/history, offline source inspection, and Work approval/denial. Work answers must expose their real retrieved evidence and either valid inline citations or an explicit visible warning that inline citations are missing; citations are never fabricated to satisfy the check. A separate native test requires a real model-generated numbered citation.

All 48 tests passed locally in the expanded-model validation pass. The combined native/UI result is `TestResults/Thimvale-expanded.xcresult` (28 passed, zero failed or skipped); the standalone core and release-configuration suites contribute eleven and nine. This pass uses the owner-registered `com.ethanrimes.thimvale` bundle identifier and covers the new Higher RAM filter, Nanbeige search, all catalog families, total-versus-active parameter labels, and retained 4B selection. Three pre-existing catalog defaults were subsequently corrected to Q8_0 because those publishers only expose Q8_0 files; all 36 preferred quantizations passed the live catalog check.

The unsigned Release archive `TestResults/Thimvale-registered.xcarchive` also passed with `com.ethanrimes.thimvale`; its bundle identifier and privacy manifest were checked. Release tests exercise credential/profile validation, build numbering, export options, and event guards without real Apple secrets. They do not establish that a signed upload succeeds.

Cloud run [34081016795](https://github.com/ethanrimes/thimvale-ios/actions/runs/34081016795) passed the build and simulator gates but failed before upload: the release helper uppercased Apple's lowercase provisioning-profile UUID, and Xcode could not find that identifier. A local comparison reproduced the lookup failure with uppercase and passed profile lookup with Apple's exact original string. The helper now validates the UUID without changing its spelling; two added regression tests cover case preservation through export and rejection of malformed identifiers. All 11 release tests pass. A new cloud run must still confirm signed archiving and upload.

A subsequent archive audit found a missing iPad portrait-upside-down declaration. The app supports iPad multitasking, so its generated plist now includes all four iPad orientations. The simulator regression reads the raw built plist (Bundle's ordinary lookup resolves orientation variants for the current iPhone) and passed in `TestResults/Thimvale-orientations-fixed.xcresult`. Three additional release tests check archive identity, build number, and complete iPad orientations; the release suite now has 14 passing tests. Run 34082479013 was intentionally stopped during simulator tests, before signing, to include this correction in the next full cloud run.

Cloud run [34083008401](https://github.com/ethanrimes/thimvale-ios/actions/runs/34083008401), commit `5487460`, then passed all 54 tests (11 core, 14 release configuration, 13 native, 16 UI), created and verified the distribution-signed archive, and uploaded **Thimvale 0.1.0 (12.1)** to App Store Connect. Xcode reported `EXPORT SUCCEEDED` at September 6, 2026, 9:49 p.m. Pacific. Apple processing and export compliance are separate from this upload result. The upload emitted a non-fatal missing-dSYM warning for the upstream prebuilt `llama.framework`; its native crash symbolication is limited until matching upstream symbols are available. No symbols were fabricated and the warning was not suppressed.

The corrected unsigned Release archive `TestResults/Thimvale-submission.xcarchive` passed the same metadata validator used before cloud upload. A six-test navigation/filter/Chat–Work/relaunch/permission smoke pass then succeeded on both iPad mini (A17 Pro) and iPhone 17 Pro, running iOS 26.1. Results are `TestResults/Thimvale-ipad-smoke-fixed.xcresult` and `TestResults/Thimvale-iphone-navigation.xcresult`. The first iPad attempt exposed a test-selector assumption: its floating navigation items have no `TabBar` ancestor. The shared test helper now handles the observed iPad icon identifiers as well as iPhone tabs. No app-navigation change was needed. iPad Chat, Models, Higher RAM filtering, Knowledge, and Permissions screenshots were inspected. This is portrait smoke coverage, not a full iPad rotation/multitasking or inference validation.

After the owner approved the exemption metadata, the generated Release archive `TestResults/Thimvale-versioned-exempt.xcarchive` passed checks for `CFBundleShortVersionString=0.1.14`, `CFBundleVersion=14.1`, and a Boolean `ITSAppUsesNonExemptEncryption=false`. Three focused simulator tests passed for app identity, the built iPad orientations, and the encryption Boolean (`TestResults/Thimvale-export-declaration.xcresult`). All 18 release tests and Actionlint passed. The visible patch now increments with each new workflow run, while retries increment only the internal build suffix. These metadata/version changes have been verified locally, not yet uploaded in a new binary.

The existing App Store Connect build 12.1 was separately confirmed `VALID`, `usesNonExemptEncryption=false`, `IN_BETA_TESTING`, and present in the Personal internal group after the approved one-time API update. Future builds use their embedded metadata rather than a manual or scripted post-upload declaration.

After the initial cosmetic rename, SHA-256 hashes of the existing installation's conversation, download, folder, model, and permission JSON records matched their pre-rename values. The owner then selected a new App Store bundle ID, `com.ethanrimes.thimvale`; this installs separately from `com.ethanrimes.pocketmind`. The earlier installation is retained, but its files and Keychain data do not automatically migrate. See [simulator regressions](simulator-regressions.md) for the reported red screen, reproduced bugs, and fixes. Tests use isolated storage and credentials rather than resetting the user's app. Simulator test sessions use a fixed inference seed; ordinary app sessions do not.

## What these checks do not establish

No physical iPhone was connected for performance or background-transfer testing. The simulator does not provide a usable background transfer daemon in this environment, so it uses a foreground session with the same download delegate, validation, and persistence code. Physical devices use the iOS background session configuration.

No full English Wikipedia download was performed during development. Its real catalog entries, download sizes, and SHA-256 metadata are loaded by the app; actual offline search was exercised against the smaller real archive. Wikipedia uses its built-in compressed full-text index plus passage reranking, not a precomputed vector for every article.

Only the small Liquid model was exercised for inference. Availability checks for the other 38 curated entries, including the [4B models](models-4b.md) and [benchmark-chart additions](model-expansion.md), do not prove runtime compatibility, quality, or memory fitness. No 4B or larger weights were downloaded or executed. Citation following and tool selection remain model-dependent; the app displays retrieved evidence and flags an answer that omits citations.

Web search's request and error paths are implemented, but no Brave API key was supplied, so a successful authenticated Brave search was not exercised. The signed cloud upload succeeded, but no signed physical-device installation was performed during these checks.

Run the commands in the README to reproduce checks. Xcode test result bundles are written locally to `TestResults/` and excluded from Git.

## September 7: reader, conversation presentation, and notices

`Thimvale-ios-feature-complete.xcresult`: 37 native/integration tests and 20 simulator UI tests passed on iPhone 17 Pro / iOS 26.1. An additional 13 Swift package tests and 18 release tests passed (88 total). The unsigned iPhone Release build succeeded. All 39 catalog entries passed live Hugging Face metadata checks.

New coverage includes real archived articles and local links without a model, external-link confirmation, malicious HTML sanitization, streamed answers outside activity blocks, compact expandable tools, tappable inline citations and collapsed sources, exact Wikipedia edition matching, reconnect throttling, cached update failures, and review-request eligibility/TestFlight exclusion. Pack notifications use the operating system and remain opt-in; actual App Store review-sheet display is controlled by Apple and cannot be validated in the simulator or TestFlight.

After moving to `ios/`, all 37 native tests and the 31 package/release checks passed again. The full UI rerun passed 19 tests but exposed a source-row tap partly hidden by the fixed composer: XCTest reported the row as hittable even though its center was covered. The test's reveal helper now scrolls the complete control above the composer. The previously failing Work/citation test then passed in `Thimvale-citation-scroll-fixed.xcresult`; no production interaction or permission behavior was changed for this correction.

## Cloud run 17: tool disclosure regression

[Run 34164804347](https://github.com/ethanrimes/thimvale-ios/actions/runs/34164804347) compiled the iPhone and simulator builds and passed 56 of 57 native/UI tests. `testWorkKnowledgeApprovalAndDenial` failed its tool-output expansion/collapse assertions, so the dependent signing/upload job correctly did not run. This was not an Apple credential, export-compliance, or compiler failure. The captured screen recording showed fading tool details overlapping the answer during a disclosure transition.

Tool expansion now uses stable, conversation-owned state rather than local state inside a lazy transcript row, and nested output insertion/removal is immediate. Tests check each expanded/collapsed state before inspecting content, keep targets clear of both the header and composer, and scroll through the outer gutter rather than a nested tool output. A separate, explicitly synthetic presentation fixture checks repeated toggles and offscreen/onscreen state retention; the real-model Work/permission/citation test remains enabled. The fixture exists only in DEBUG simulator builds with isolated test storage.

The CI workflow now saves successfully bootstrapped native dependencies before running tests, using separate cache restore/save actions. A later UI failure no longer discards five minutes of native compilation. The full test gate, automatic patch numbering, signing validation, and `main` TestFlight upload requirement are unchanged.

Local verification of this correction passed all 37 native integration tests, 21 UI tests, 13 Swift package tests, and 18 release checks (89 total). Both Debug and Release iPhone builds succeeded, and both GitHub workflows passed `actionlint`. The complete simulator result is `TestResults/Thimvale-ci18-full.xcresult`; the presentation-fixture strings were also confirmed absent from the Release device executable. Cloud and Apple processing status must still be checked independently after pushing.
