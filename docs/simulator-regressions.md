# Simulator regression pass

## Reported red screen

The September 6 screenshot showed React Native's “No script URL provided” error. Simulator logs at 18:35:18 recorded installation of `NexoERP.app`; at 18:35:19 they recorded CoreSimulator launching `com.ethanrimes.nexo` over PocketMind. The foreground scene belonged to Nexo, not `com.ethanrimes.pocketmind`. The status-bar “◀ PocketMind” label was the system return button.

PocketMind contains native SwiftUI/C++ code and no JavaScript runtime. It was brought back to the foreground without changing Nexo, deleting its installation, or starting a Metro server. `scripts/run-simulator.sh` now provides an unambiguous build/install/launch command using PocketMind's bundle identifier.

## Bugs reproduced and fixed

- **Lost draft without a model.** The composer cleared its text before `AppState.send` could reject the request. The regression failed with an empty composer after returning from Models. Sending now reports whether the message was accepted, and only accepted messages clear the draft. Empty, oversized, and missing-model requests never enter conversation history.
- **Knowledge import buttons did nothing.** Stacked file-importer modifiers prevented the file picker from appearing for “Add files.” Knowledge now uses a single importer with an explicit files/folder/archive mode. The regression opens and cancels each picker in sequence.
- **Tool syntax displayed as an answer.** The small test model sometimes emitted its own function-call notation instead of the supported JSON format. Unsupported syntax is never executed. When passages are available, a single answer-only retry uses those passages without tool access. Empty or still-malformed responses produce an explicit error instead of masquerading as answers.
- **Natural-language Wikipedia queries missed articles.** The fallback reused SQLite's query expression for libzim. It now strips conversational wording, tries plain search terms, and bounds per-term fallback. Definition questions favor introductory passages when relevance is otherwise similar. A native integration test checks the actual Bowline article using a complete question.
- **Approval prompts for invented folders.** The model copied an example folder identifier from its instructions. Unconnected folder identifiers are now rejected before asking for approval, and permissions are still checked again after approval. A failed tool can fall back to an answer from existing sources, with the failure provided explicitly so it must not claim the action succeeded.

The exploratory tests also exposed test issues: a math-answer assertion expected exactly `4` although the real model correctly replied “Two plus two equals 4.”; a Settings navigation query matched both a back button and the underlying toolbar; and tapping the center of a switch's accessibility row hit its label rather than the control. Assertions now wait for generation to finish, target the intended navigation bar, and tap the switch control. Work's answer check requires an explanation, an inline citation linked to a real source card, and no raw tool-call expression.

## Reproducing the checks

```sh
./scripts/fetch-test-assets.sh
xcodebuild test -project PocketMind.xcodeproj -scheme PocketMind \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath TestResults/Simulator.xcresult CODE_SIGNING_ALLOWED=NO
```

UI tests use separate UUID-named app storage, preferences, and Keychain services. Fixture-enabled tests import an actual GGUF, an actual Wikipedia ZIM, and the small text document under `Tests/Fixtures`. They do not substitute generated answers or search results. Fixture loading is available only in Debug simulator builds.

This is a bounded regression pass, not proof that every model, device, accessibility setting, or future upstream response is error-free. See `validation.md` for the physical-device and background-transfer limitations.
