# Set up Thimvale on TestFlight

Instructions checked against Apple and GitHub documentation on September 6, 2026.

The repository already has the cloud workflow. After the one-time setup below, a push to `main` runs tests on GitHub, builds a signed Release archive, and uploads it to your registered App Store Connect app. Pull requests never upload. A failed test blocks release. Apple still has to process each uploaded build; uploading does not publish the app on the App Store or submit it for review.

**Setup status (September 6, 2026):** the owner registered the Thimvale app and its Personal internal-testing group. The supplied API key and distribution identity were validated, all six GitHub Secrets and the Team ID were configured, and a separate App Store provisioning profile was created for `com.ethanrimes.thimvale`. `TESTFLIGHT_ENABLED` is `true`. The first signed cloud upload succeeded: **0.1.0 (12.1)**, [run 34083008401](https://github.com/ethanrimes/thimvale-ios/actions/runs/34083008401). All 54 cloud tests passed. Apple finished processing; after the owner approved the encryption exemption, build 12.1 was confirmed `IN_BETA_TESTING` and present in the Personal group. The owner's existing testers do not need to be recreated.

## 1. Enroll and record your Team ID

1. Sign in at [Apple Developer](https://developer.apple.com/account/) with your Apple Account and enable two-factor authentication.
2. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/enroll/) if you are not already a member. The standard price is US $99/year, with regional pricing. A free Personal Team cannot distribute through TestFlight. Choose Individual for your personal account or Organization for a qualifying legal entity.
3. Accept the required agreements yourself. No agreement, enrollment, or payment has been accepted on your behalf.
4. In your developer account's membership details, copy the 10-character **Team ID**. This is different from an App Store Connect API Issuer ID.

## 2. Register the App ID and app record

In Apple Developer → Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App:

- Description: `Thimvale`
- Bundle ID type: **Explicit**
- Bundle ID: `com.ethanrimes.thimvale`
- Do not enable unrelated capabilities such as iCloud, push notifications, or App Groups. The app does not require them.

Register it, or reuse it if it is already registered to your team. The owner selected this bundle identifier for the App Store Connect app. It is a separate installation from the earlier `com.ethanrimes.pocketmind` simulator prototype: sandbox files, preferences, and Keychain access do not automatically transfer between bundle IDs. The old installation has not been deleted. [Apple's App ID instructions](https://developer.apple.com/help/account/identifiers/register-an-app-id).

In [App Store Connect](https://appstoreconnect.apple.com/) → Apps → **+** → New App, enter:

| Field | Value |
| --- | --- |
| Platform | iOS |
| Name | Thimvale |
| Primary language | English (U.S.), or your preferred primary language |
| Bundle ID | The explicit `com.ethanrimes.thimvale` identifier above |
| SKU | `thimvale-ios-001` |
| User access | Your account; restrict other users as appropriate |

Click Create. This is the authoritative check for whether Apple will accept/reserve the name; public searches cannot detect unpublished reservations. Creating the record does not publish an app. Do not change the bundle ID after the first upload. [Apple's new-app instructions](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app), [identifier and SKU rules](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information).

## 3. Create an exportable distribution certificate and profile

The GitHub runner needs both a signing certificate **with its private key** and a matching provisioning profile. Your App Store Connect API key alone is not the signing identity used by this workflow.

1. On your Mac, open Xcode → Settings → Accounts (Apple Accounts in some versions), add your Apple Account, and select the paid developer team.
2. Click Manage Certificates → **+** → **Apple Distribution**. Use an existing valid local distribution identity if appropriate; do not revoke certificates used by other apps.
3. Control-click that certificate → Export Certificate. Save an encrypted `.p12`, for example `ThimvaleDistribution.p12`, outside this repository. Set a strong export password and retain it securely. A `.cer` download alone is insufficient because it lacks the private key. A cloud-managed-only certificate cannot be exported from your local Keychain. [Apple's signing identity export instructions](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates).
4. In Apple Developer → Profiles → **+**, choose **App Store Connect** under Distribution, not Development, Ad Hoc, or Enterprise.
5. Select the Thimvale App ID, then the **same distribution certificate** you exported. Name the profile `Thimvale App Store`, generate it, and download the `.mobileprovision` file. [Apple's profile instructions](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile).

You do not need to register your iPhone's UDID for TestFlight. Retain these files securely; replace the GitHub secrets when the certificate/profile expires or is rotated.

## 4. Create the upload API key

1. App Store Connect → Users and Access → Integrations → App Store Connect API.
2. If prompted, the Account Holder must request API access and accept the terms. Wait for access to be enabled.
3. Under **Team Keys**, generate a key named `Thimvale GitHub` with the **Developer** role (sufficient for build uploads; no Admin key is needed for this workflow).
4. Download the `.p8` file. It can be downloaded only once.
5. Record its **Key ID** and the team's **Issuer ID** from that page.

This workflow expects a team key, not an individual key. Team keys can affect all apps permitted by their role; protect and revoke them appropriately. Never paste the private key or P12 contents into chat or commit them. [Apple's API key setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/).

## 5. Add the GitHub configuration

Open [repository Actions settings](https://github.com/ethanrimes/thimvale-ios/settings/secrets/actions). Under **Secrets**, add these repository secrets:

| Secret name | Value |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Base64 contents of the exported `.p12` |
| `IOS_DISTRIBUTION_P12_PASSWORD` | The `.p12` export password |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64 contents of the `.mobileprovision` |
| `APP_STORE_CONNECT_KEY_ID` | The upload key's 10-character Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Its UUID-shaped team Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Entire raw `.p8` contents, including BEGIN/END lines; **not Base64** |

On a Mac, these commands copy encoded files to your clipboard without printing the credentials in Terminal. Adjust the filenames to the files you downloaded:

```sh
base64 -i /absolute/path/ThimvaleDistribution.p12 | pbcopy
base64 -i /absolute/path/Thimvale_App_Store.mobileprovision | pbcopy
```

Run one command, paste into its matching GitHub secret, then do the next. Clear your clipboard afterward. [GitHub's certificate/secret guidance](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

Under the **Variables** tab, add/update:

| Variable name | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID |
| `TESTFLIGHT_ENABLED` | `true`, only after all six secrets and the app record are ready |

These are repository variables, not secrets. Do not put private keys in Variables. Only trusted maintainers should have write access to `main` or be able to edit the release workflow. Configure branch protection to require review if others collaborate. Never enable privileged `pull_request_target` uploads.

## 6. Run the first cloud upload

1. Open GitHub → Actions → **iOS** → Run workflow → branch **main** → Run workflow. This first manual trigger avoids an unnecessary empty commit. Future pushes to `main` run automatically.
2. The `build` job bootstraps pinned libraries, runs core/release-configuration tests, compiles for iPhone/simulator, and exercises native/UI tests with real downloaded fixtures.
3. After it passes, **Archive and upload to TestFlight** imports the temporary signing identity, checks profile expiry/team/bundle/certificate, creates a Release archive, verifies the app name/version/build/privacy manifest/encryption declaration, and uploads using the API key. Both the visible version and internal build number are generated automatically as described below.
4. The runner removes its temporary credentials and restores the profile/keychain state. GitHub destroys the hosted VM afterward. Signing material and archives are not uploaded as GitHub artifacts; test result bundles are retained for seven days.
5. Watch App Store Connect → Thimvale → TestFlight → iOS for Apple processing. An upload success is not an Apple processing or review approval. If a job is skipped, check the enable variable; if blocked, inspect the failing step rather than bypassing tests.

The cloud runner pins Xcode 26.1.1 on macOS 15 and the iPhone 17 Pro/iOS 26.1 test destination to match local validation. Runner defaults had advanced to Xcode 26.6: one cloud UI run failed to activate navigation controls, while the following run passed. Pinning makes the release environment reproducible; it is not a claim that the cause of that intermittent failure was established. Apple currently requires Xcode 26+ and an iOS 26+ SDK for uploads. The app's deployment target remains iOS 18. [Apple SDK requirements](https://developer.apple.com/news/upcoming-requirements/), [build processing](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [GitHub runner software](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md).

### Automatic versions

The release job's `THIMVALE_VERSION_SERIES` is `0.1`; `release.py` appends GitHub's workflow run number as the patch. Run 14 therefore uploads `0.1.14`, run 15 uploads `0.1.15`, and so on. The internal `CFBundleVersion` remains `run.attempt`: retrying run 14 uses visible version `0.1.14` with build `14.2`. Failed, canceled, or pull-request runs can leave gaps; version numbers are increasing, not necessarily consecutive among uploaded releases. The first upload predates this scheme and remains `0.1.0 (12.1)`.

No CI-generated version commit or tag is needed, so bumping the version cannot trigger an extra build. Local development builds retain `project.yml`'s base version unless explicitly overridden. To change major/minor, update the release workflow's series and the local base version together. Do not retry an older run after newer releases have shipped; dispatch a new run instead.

### Export compliance

The owner approved the reviewed encryption exemption. `project.yml` now sets `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO`, and the generated Release app was verified to contain the Boolean `ITSAppUsesNonExemptEncryption = false`. App Store Connect reads this metadata on each future upload, avoiding the repeated questionnaire while the declaration remains accurate. No per-upload manual declaration or API patch is part of the pipeline. The release validator rejects a missing, true, or incorrectly typed value before upload. [Apple's metadata instructions](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).

The review found iOS-provided HTTPS/Keychain and hashing, with no separate encryption implementation identified in the linked libraries. The declaration concerns encryption use, not geographic distribution: it does not set U.S.-only availability or remove other applicable obligations. Changes to encryption or bundled dependencies require reassessment. [Apple's encryption guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).

Build 12.1 had already been uploaded without that key, so the same owner-approved exemption was applied once to that exact build through Apple's API. Apple then reported `IN_BETA_TESTING`, and the Personal group included it. New builds carry the declaration in their own metadata instead.

## 7. Invite yourself and install

1. App Store Connect → Thimvale → TestFlight → **+** next to Internal Testing.
2. Create a group called `Personal` and select **Enable automatic distribution**.
3. Click Invite Testers and add your own App Store Connect user. Use your normal Apple Account, not a sandbox-purchase account. No external tester group or public invitation link is needed for your own device.
4. If the first eligible build is not added automatically, click Add Builds and select it. Enter What to Test, for example: “Download a small model, send a chat, import a text file, and ask a Work question with a citation.”
5. Install Apple's [TestFlight app](https://apps.apple.com/us/app/testflight/id899247664) on your iPhone. Open the invitation email on that phone, accept it in TestFlight, and install **Thimvale**.
6. Open Models and download a small model over Wi-Fi. Models and Wikipedia are not bundled with the app. Download the desired corpus before trying airplane-mode Q&A. Actual iPhone performance and background behavior still need this device test.

Subsequent eligible uploads go to the automatic internal group once Apple processes them and compliance is satisfied. Builds expire after **90 days**, even if the model and corpus remain on the phone; install a newer build before expiry. Uploading to TestFlight does not make the app publicly searchable on the App Store. [Apple's internal-testing instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers), [TestFlight lifecycle](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## Later: other testers or the public App Store

The workflow's uploads are eligible for external testing, but it does not create external groups, submit Beta App Review, or release a public app. For those, add the required beta description, feedback address, review contact/instructions, privacy policy, and other requested metadata; the first external build requires Apple's beta review. [Apple's test-information instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information).

The app includes GPL-licensed Kiwix libraries. Before distributing to others, provide recipients the corresponding source and review the chosen distribution terms; a private GitHub link alone will not give testers access. No public-repository visibility change or licensing clearance has been performed. [GNU's source-distribution guidance](https://www.gnu.org/licenses/gpl-faq.en.html#SourceAndBinaryOnDifferentSites). Review model licenses separately; weights are user-downloaded rather than included in the binary.

## Common setup failures

- **Signing job skipped:** `TESTFLIGHT_ENABLED` is not the exact string `true`, the run is a PR, or the build/test job failed.
- **Missing configuration:** the preflight lists missing names, never secret values. Recheck Secrets versus Variables.
- **Certificate does not match:** export the certificate with its private key and regenerate the profile selecting that same certificate. Do not use an Apple Development certificate.
- **Wrong profile:** use App Store Connect distribution with the explicit bundle ID and correct team; not an Ad Hoc/device profile.
- **Profile installed but not found:** preserve the exact UUID from Apple's signed profile, including letter case. Do not uppercase or otherwise normalize it for Xcode's profile selector.
- **Invalid iPad orientations:** the app supports iPad multitasking and must declare all four orientations. The native test and pre-upload archive check guard this setting. [Apple's multitasking configuration](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/AdoptingMultitaskingOniPad/QuickStartForSlideOverAndSplitView.html).
- **Upload unauthorized/app not found:** check team Key ID/Issuer ID/raw `.p8`, key role, active agreements, and the pre-created app record's bundle ID.
- **Build number already used or lower:** dispatch a new run on current `main`; don't rerun an old commit after newer builds have shipped. If you upload manually too, coordinate build numbers with CI.
- **Build remains unavailable:** check Apple's processing error email, export compliance, and the internal group's build membership.
- **Expired build/certificate/profile:** upload a fresh build and rotate the relevant signing secrets when needed. Do not revoke credentials used by other apps without coordinating that change.
