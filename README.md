# Thimvale

Local models, controlled tools, and offline knowledge for your phone.

This repository contains both native apps:

- [`ios/`](ios/README.md): SwiftUI, llama.cpp/Metal, Kiwix, compressed local retrieval. Includes the existing TestFlight release pipeline.
- [`android/`](android/README.md): Kotlin/Jetpack Compose, llama.cpp/JNI, Kiwix, Android document access and background downloads.
- [`shared/`](shared/): model catalog and shared licensing assets. `scripts/sync-catalog.py` regenerates the Android catalog from the curated iOS entries; CI checks for drift.

The GitHub repository URL is unchanged, so existing clones, secrets, and App Store Connect registration continue to work. The production application identifier remains `com.ethanrimes.thimvale` on both platforms; Android debug builds use a `.debug` suffix.

Every push to `main` runs the iOS checks and, with the existing release secrets, uploads to TestFlight. Superseded iOS runs are cancelled. Android has a separate Linux build workflow and downloadable APK artifact; Google Play publication requires a separate Play Console registration and release signing setup.

Source: GPL-3.0-or-later. Model weights and Wikipedia content retain their own licenses. See each platform's README for build instructions, tested behavior, and limitations.
