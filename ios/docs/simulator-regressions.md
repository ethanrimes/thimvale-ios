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

The app has since been renamed **Thimvale**. The incident above retains its original app names and bundle identifiers.

```sh
./scripts/fetch-test-assets.sh
xcodebuild test -project Thimvale.xcodeproj -scheme Thimvale \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath TestResults/Simulator.xcresult CODE_SIGNING_ALLOWED=NO
```

UI tests use separate UUID-named app storage, preferences, and Keychain services. Fixture-enabled tests import an actual GGUF, an actual Wikipedia ZIM, and the small text document under `Tests/Fixtures`. They do not substitute generated answers or search results. Fixture loading is available only in Debug simulator builds.

This is a bounded regression pass, not proof that every model, device, accessibility setting, or future upstream response is error-free. See `validation.md` for the physical-device and background-transfer limitations.

## Thimvale rename and release-flow follow-up

The approval UI test could see the old Deny button while a just-approved sheet was animating away. It now waits for dismissal before handling any new request. Isolated Debug simulator inference uses a fixed random seed so the real-model regression is repeatable; production sampling is unchanged.

The small model also sometimes returns a bibliography without numbered inline citations, even after the bounded retry. This was already recorded in the work activity, but the app now shows an explicit warning beside the retrieved sources as well. The Work UI test verifies either a valid numbered citation or the visible missing-citation warning, and always checks that the original source is inspectable. The separate real-inference integration test still requires a numbered citation. The suite does not pretend every small-model answer is accurate or correctly cited.

## Cloud run 20: attachment deadlines and model-search stall

[Run 34186935105](https://github.com/ethanrimes/thimvale-ios/actions/runs/34186935105) compiled both device and simulator apps but failed three simulator tests. The dependent archive/upload job was skipped; this was not a signing or App Store Connect rejection.

- The real image-chat and attached-text tests inspected their answers after a fixed 30-second polling loop, even though generation was still active. The image test then attempted its release/reload follow-up while the first turn was cancelling, producing secondary failures. They now await completion with a monotonic, bounded 180-second allowance for cold inference on hosted simulators. A timeout cancels, drains cancellation for up to ten seconds, and throws with stage/model/response-length diagnostics. It does not continue into final-answer assertions. Scripted tests retain a five-second default, and a separate regression requires a deliberately delayed generation to time out and cancel cleanly. Pixel-dependent answers, citations, streaming events, and unload/reload assertions are unchanged.
- The navigation recording froze with only `G` entered in the model search. The app log reports its main thread not responding; the later broad accessibility query timeout was a symptom, not sufficient evidence of the underlying framework cause. The small catalog (40 curated entries; Hub searches also cap at 40) now uses eagerly laid-out rows instead of a nested lazy stack during simultaneous search-result, suggested-card, and keyboard changes. The test uses the existing stable model-row identifier. A new regression repeatedly types one character, narrows results, clears back to the full catalog, switches families by search, submits/dismisses the keyboard, and navigates back to Chat.

The layout change is a mitigation for the observed transition, not a claim that the exact SwiftUI internals responsible were isolated. Local repeat runs and the subsequent hosted gate are both needed. No test is skipped or automatically retried to turn a genuine failed assertion green; no production inference token budget or sampling behavior is changed.

Local validation on iPhone 17 Pro / iOS 26.1: all 11 attachment integration tests passed (including optional Qwen vision); all five navigation cases plus the vision-filter case passed twice each after the layout change (12 UI executions, no failures). The new search case performs three type/clear cycles per execution. The 13 core tests, 23 release-validation tests, and workflow lint also passed. These results do not substitute for the hosted build or Apple's processing confirmation.
