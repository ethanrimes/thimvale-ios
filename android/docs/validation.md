# Android validation

## Environments

Local builds use JDK 17, SDK 36, NDK 28.2.13676358, CMake 3.22.1, Gradle 8.13, and the committed wrapper checksum. Device/UI tests run on a dedicated Android 15 (API 35) ARM64 emulator with 6 GB RAM. Native integration was also exercised on an API 37 emulator with 16 KB memory pages. The current Espresso dependency cannot run UI tests on API 37 because that OS removed the hidden `InputManager.getInstance` method; the API 35 UI run is the supported test lane.

## Coverage

September 7, 2026: all thirteen API 35 device tests passed (79.8 seconds). Debug APK, unsigned release AAB, lint, catalog, and native alignment checks passed. A subsequent visual check found an HTML nesting error in collapsed article facts; a focused regression test covers that correction.

- Ten local unit tests: tool parsing, streamed presentation, exact labeled source excerpts, safe article HTML, permissions, exact Wikipedia edition matching, review cadence, catalog integrity, and retrieval helpers.
- Thirteen device tests: real llama.cpp generation and retained weights, cancellation/reload, real ZIM browsing/full text, live remote metadata, local atomic persistence, Compose navigation/settings/presentation, permission revocation, offline cited answers, Storage Access Framework read/create/index/disconnect, and actual DownloadManager transfers with accepted and rejected SHA-256 checksums.
- Lint, debug APK, and unsigned release AAB builds.
- All 14 packaged native libraries across ARM64 and x86-64 checked for 16 KB ELF alignment, plus APK page alignment.

The runtime tests use a checksum-pinned LFM2.5-230M GGUF and a real July 2026 English Wikipedia knots pack. Small models can ignore tool/citation instructions: malformed calls never execute, are recorded as failed activity, and a bounded answer-only recovery may retry against the retrieved passages. If that retry still fails to cite, the app displays a labeled, exact source excerpt with its real reference instead of attaching citations to generated claims. Only returned source IDs become links. Missing/unknown references remain visible as warnings; the app does not fabricate citations.

The debug-only document provider exposes only test fixtures under the debug app's cache. Tests create unique paths and remove their own temporary artifacts; they do not clear production app data. A background-download test temporarily enables cellular downloads because the dedicated emulator presents a metered connection, then restores the preference.

## Limits

This is an initial Android implementation, not a claim of full iOS feature parity. Inference is CPU-only; local indexing uses compressed text, full-text search, and lexical vectors, not semantic sentence embeddings. PDF extraction and conversation export are not included. No physical Android phone, all 39 model weights, full-English multi-GB Wikipedia pack, Google Play review dialog, or production Play upload has been validated. Native store review APIs control whether a prompt appears and expose no submitted-review status.

The root Android workflow repeats unit tests, lint, builds, catalog drift checks, and native alignment checks on Linux. It publishes build artifacts, not a signed Play release. Device integration tests currently run locally with the explicitly installed fixtures.
