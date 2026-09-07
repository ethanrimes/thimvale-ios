# Offline Wikipedia reader

Open **Knowledge → Read Wikipedia offline** and select a downloaded or imported indexed ZIM pack. This screen does not fetch the catalog or load a language model. The empty state offers a separate, explicit download action.

- Browse article titles in pages of 40, or search the selected pack's existing full-text index. No second corpus or vector index is created. Query changes cancel obsolete UI requests and reset pagination.
- Open the stored article, not just the short excerpt used for Q&A. Headings, paragraphs, lists, tables, footnotes, and links are preserved in a text-focused reader. Mini packs still contain abridged articles; the reader cannot recover text missing from the pack.
- Follow relative article links and English Wikipedia `/wiki/` links within the selected archive. ZIM redirects resolve to canonical article paths. Section links stay within the document. Native Back navigation retains the previous page/search.
- Missing pages report that they are absent from this edition, without falling back to the internet. External HTTP(S) links require confirmation before opening the system browser. Source attribution is visible; the online source links to Wikipedia's contributor history and licensing information.
- Archive HTML is untrusted: a SwiftSoup allowlist removes scripts, archive styles, forms, frames, resource-bearing attributes, and images. JavaScript from content is disabled in a nonpersistent WKWebView; a restrictive content-security policy blocks resource requests. The navigation delegate permits only the initial app-supplied HTML. Section taps use an app-authored, safely escaped scroll operation instead of loading a URL. Article navigation is intercepted and served by libzim, never by a web server.
- Images, media, source scripts, and interactive Wikipedia widgets are not rendered. HTML pages above 4 MiB are rejected with an explicit error, not silently truncated. The compressed pack is read on demand; it is not extracted in full. Native archive calls stay serialized on the knowledge-service actor.

Tests use the existing checksum-pinned July 2026 Wikipedia knots ZIM. They cover metadata-only pagination, full article retrieval, missing pages, input boundaries, sanitization, link normalization, and browsing with no selected model. This is not a claim of having loaded every article in a full English Wikipedia pack.

Reference: [libzim archive API](https://libzim.readthedocs.io/en/latest/api/classzim_1_1Archive.html), [Apple's content JavaScript setting](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript).

## Pack updates and notifications

With downloaded packs installed, the app checks Kiwix's catalog when it reconnects in the foreground, and at most once per six hours during ordinary foreground use. Rapid reconnects are throttled; **Knowledge → Wikipedia updates → Check now** checks immediately. Failed checks keep the last successful catalog. Checks send no questions, article searches, or imported text to Kiwix.

Updates match the exact topic and edition (`mini`, `nopic`, or `maxi`) and require a newer dated filename. Renamed or unversioned imports cannot be matched automatically. An in-app banner announces newly discovered editions. **Settings → Wikipedia update alerts** optionally enables local system notifications; notification permission is requested only when that switch is enabled. Tapping an alert opens the update screen. No push server is involved. A closed app cannot run arbitrary network checks: the next foreground/reconnect check discovers updates.

Downloading an update requires confirmation. These are complete replacement packs, not deltas; sufficient space for both editions is required. The existing background downloader verifies size and checksum before publishing the new file. The old pack remains available, including if an update fails. Q&A prefers the newest installed edition of each exact series. Remove the old edition manually after verifying the new one; nothing is silently deleted.

## App Store reviews

Production App Store builds may request Apple's native StoreKit review sheet after at least five chat interactions and seven days of use, with a 120-day cooldown and no repeat request for the same version. Apple controls whether the sheet is shown. Development and TestFlight builds never request it. Settings allow disabling requests or marking **I've already reviewed**; Apple does not provide an API to determine whether a review was submitted.

There are no review-request notifications or custom rating dialogs. Apple requires the provided review API and disallows custom review prompts ([App Review Guideline 5.6.1](https://developer.apple.com/app-store/review/guidelines/#app-store-reviews)). Requests do not depend on sentiment, a positive rating, or rewards. Review cadence and notification preferences remain on the device.
