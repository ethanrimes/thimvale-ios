# Thimvale for Android

Native Kotlin and Jetpack Compose with llama.cpp/JNI and libkiwix. Android 9 or newer; ARM64 phones and x86-64 emulators. This is not a WebView app: only sanitized offline article content uses Android's HTML renderer.

## Build

Install Android Studio, JDK 17, Android SDK 36, NDK `28.2.13676358`, and CMake `3.22.1`. Set `ANDROID_HOME` to your Android SDK or configure `sdk.dir` in an untracked `local.properties` file.

```sh
cd android
./scripts/bootstrap.sh
./gradlew testDebugUnitTest lintDebug assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open this directory in Android Studio to run or debug. The Gradle wrapper pins 8.13, AGP 8.13.2, Kotlin 2.3.20, and the Compose January 2026 BOM compatible with SDK 36. Bootstrap pins llama.cpp b10830 and checks source/header digests. A release bundle can be built with `./gradlew bundleRelease`; it is deliberately unsigned until a release identity is configured. Never commit signing keys or local API tokens.

## Use

1. **Models:** browse the shared 40-model catalog, including 4B entries, or search Hugging Face. Open a repository, review the license, and choose a single-file GGUF. Add a Hugging Face token in Settings for gated repositories, after accepting their terms on the model card. Android currently has text input only: the new iOS attachment/MTMD vision flow is not ported here. Safetensors, sharded GGUFs, and vision projectors are not supported on Android.
2. **Downloaded → Use model:** selecting a model loads its weights. Chats reuse the same in-memory model; backgrounding or five minutes without a request releases it. The next message reloads as needed. This initial Android runtime uses CPU inference, not Metal/Vulkan acceleration. RAM labels are guidance, not a guarantee a model will fit.
3. **Chat / Work:** chat streams into the conversation. Work can search knowledge, list folders, read files, create new files, and search the web. Tool rows are compact and expandable. Inline citation IDs open the actual returned source; the complete source list starts collapsed. Model output and tool results stay in local conversation history.
4. **Permissions:** independently choose Off, Ask, or Allow for each capability. Ask previews the actual arguments. Permission is rechecked after approval; retrieved content cannot grant access. File creation refuses overwrites. Web search needs a Brave API key and sends the permitted query to Brave.
5. **Knowledge:** connect a folder through Android's Storage Access Framework and explicitly index its UTF-8 TXT, Markdown, CSV, JSON, HTML, or log files. Reindex replaces the folder's old passages in a transaction; disconnect removes them. Limits: 1 MB/file, 1,000 files, 12 directory levels, and 16 million text characters per folder. Imported documents and other apps' private directories are not exposed automatically.
6. **Wikipedia:** download or import an indexed ZIM, browse/search its stored articles, and follow local links without a model. Packs stay compressed; there is no giant extraction or separate per-article vector download. Mini editions are abridged; full English text still takes many GB. HTML is sanitized, scripts/resources/network loads are blocked, and external links require confirmation.
7. **Updates and notices:** foreground/reconnect checks discover newer matching pack editions. Downloads require confirmation and keep the old version; Q&A chooses the latest installed edition. An in-app notice and opt-in local system alerts announce updates. Closed apps do not perform arbitrary update checks.

Downloads use Android DownloadManager and WorkManager verification. They can continue after leaving the app; Android scheduling, force-stop, connectivity, signed-URL expiration, and storage limits can pause or fail a transfer. Files aren't published until byte size, SHA-256, and format magic are verified. Check Downloads in Knowledge for progress/errors/cancellation. Imported files have no publisher checksum and are checked for format before use.

Review requests use Google's native Play review API with a seven-day/five-interaction threshold, 120-day cooldown, and per-version limit. They are disabled in debug/non-Play installs. Users can opt out or mark “I've already reviewed”; Google does not reveal whether a review was submitted. There are no custom rating dialogs, rewards, or review notifications.

## Current platform differences

The Android index uses losslessly deflated passages, SQLite full-text search, and 2,048-bit **lexical** feature vectors. It is not the iOS semantic sentence-embedding implementation. PDF text extraction, semantic sentence embeddings, GPU acceleration, and conversation export are not included in this initial Android release. Only text chat is supported on both platforms. A curated listing is not a claim that every model has been inference-tested on Android.

App data is excluded from cloud backup and device transfer. API tokens are encrypted with Android Keystore. No telemetry or push server is present. Knowledge text and chat stay local unless the user explicitly authorizes a web query or opens an external link. Kiwix receives catalog/download requests; Hugging Face receives model searches/download requests.

## Tests

```sh
./gradlew testDebugUnitTest lintDebug assembleDebug assembleDebugAndroidTest
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
./scripts/install-test-fixtures.sh emulator-5556
adb -s emulator-5556 shell am instrument -w -r \
  com.ethanrimes.thimvale.debug.test/androidx.test.runner.AndroidJUnitRunner
python3 scripts/check-native-alignment.py app/build/outputs/apk/debug/app-debug.apk
```

Fixtures are the same checksum-pinned 230M Liquid GGUF and real July 2026 Wikipedia knots ZIM used by iOS. Native integration tests exercise actual streamed generation, reuse, cancellation, release/reload, full-article retrieval, and live download metadata. Device tests also cover scoped document read/create/index/disconnect, verified background downloads and checksum rejection, permission revocation, real offline Q&A, inline citations, and collapsed source/tool details. No test clears production data. The debug package has a separate `.debug` application ID; its test document provider is absent from release builds. See [validation notes](docs/validation.md).

The root Android workflow builds on Linux and uploads APK/AAB artifacts. It does not publish to Google Play. Create a Play Console app and configure an upload signing key before Play distribution; the iOS TestFlight setup is unaffected.

References: [llama.cpp Android runtime](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md), [Kiwix Java/Kotlin bindings](https://github.com/kiwix/java-libkiwix), [Android 16 KB support](https://developer.android.com/guide/practices/page-sizes), [Play review API](https://developer.android.com/guide/playcore/in-app-review). Shared licenses are bundled under `assets/licenses/`; source remains GPL-3.0-or-later.
