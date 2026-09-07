# Simulator regression pass

## Reported red screen

The September 6 screenshot showed React Native's “No script URL provided” error. Simulator logs at 18:35:18 recorded installation of `NexoERP.app`; at 18:35:19 they recorded CoreSimulator launching `com.ethanrimes.nexo` over PocketMind. The foreground scene belonged to Nexo, not `com.ethanrimes.pocketmind`. The status-bar “◀ PocketMind” label was the system return button.

PocketMind contains native SwiftUI/C++ code and no JavaScript runtime. It was brought back to the foreground without changing Nexo, deleting its installation, or starting a Metro server. `scripts/run-simulator.sh` now provides an unambiguous build/install/launch command using PocketMind's bundle identifier.

## Bugs reproduced and fixed

- **Lost draft without a model.** The composer cleared its text before `AppState.send` could reject the request. The regression failed with an empty composer after returning from Models. Sending now reports whether the message was accepted, and only accepted messages clear the draft. Empty, oversized, and missing-model requests never enter conversation history.
- **Knowledge import buttons did nothing.** Stacked file-importer modifiers prevented the file picker from appearing for “Add files.” Knowledge now uses a single importer with an explicit files/folder/archive mode. The regression opens and cancels each picker in sequence.

The exploratory tests also exposed two test issues: a math-answer assertion expected exactly `4` although the real model correctly replied “Two plus two equals 4.”, and a Settings navigation query matched both a back button and the underlying toolbar. Those assertions now inspect the assistant message and the intended navigation bar respectively.

## Reproducing the checks

```sh
./scripts/fetch-test-assets.sh
xcodebuild test -project PocketMind.xcodeproj -scheme PocketMind \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath TestResults/Simulator.xcresult CODE_SIGNING_ALLOWED=NO
```

UI tests use separate UUID-named app storage, preferences, and Keychain services. Fixture-enabled tests import an actual GGUF, an actual Wikipedia ZIM, and the small text document under `Tests/Fixtures`. They do not substitute generated answers or search results. Fixture loading is available only in Debug simulator builds.

This is a bounded regression pass, not proof that every model, device, accessibility setting, or future upstream response is error-free. See `validation.md` for the physical-device and background-transfer limitations.
