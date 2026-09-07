# Thimvale: name screening and rename

Checked September 6, 2026 (America/Los_Angeles), before renaming this repository.

**Thimvale** is pronounced “THIM-vayl.” It is a coined name with the feel of something small and personal, without making a claim about the model's capabilities.

## Public-use checks

| Check | Observed result |
| --- | --- |
| Exact web queries: `"Thimvale"`, `"Thimvale" app software`, `"Thimvale" trademark`, `"Thimvale" OR "Thim Vale"` | No results returned |
| Indexed Apple App Store and Google Play pages | No results for `"Thimvale" site:apps.apple.com OR site:play.google.com` |
| Apple Search API, software, limit 200; US, UK, Canada, Australia, Germany, India, Japan | No returned app title contained “thimvale” (case-insensitive). US/UK/CA/AU returned seven unrelated fuzzy matches; DE/IN/JP returned zero results. |
| GitHub repository search, `thimvale in:name` | Zero repositories before this rename |
| GitHub user search, `thimvale` | Zero users |
| Verisign `.com` RDAP lookup | HTTP 404 for `thimvale.com`; no registration record returned |

Direct sources for repeating the structured checks: [Apple US software search](https://itunes.apple.com/search?term=Thimvale&entity=software&country=us&limit=200), [GitHub repository API](https://api.github.com/search/repositories?q=thimvale+in%3Aname&per_page=100), [GitHub user API](https://api.github.com/search/users?q=thimvale&per_page=100), and [Verisign RDAP](https://rdap.verisign.com/com/v1/domain/thimvale.com). Replace Apple's `country` parameter to repeat the other storefront checks. GitHub results will include this project after the rename if it becomes public; it is currently private.

These checks found no exact-name conflict in the sources examined. They do **not** prove worldwide non-use, clear similar-sounding marks, reserve an App Store name, or constitute a trademark clearance search. Unpublished apps, private projects, unindexed businesses, and registrations may not appear. A missing RDAP record is not a purchase or guarantee that a registrar will sell a domain. No domain was registered, no trademark was filed, and no App Store name was reserved.

## Implementation and existing installations

The app's visible name, assistant label, Settings, acknowledgments, Xcode project, Swift modules, development commands, and GitHub repository now use Thimvale. Test environment flags use the `THIMVALE_` prefix.

The original `com.ethanrimes.pocketmind` bundle identifier remains unchanged intentionally. The Application Support subdirectory, Keychain service, and background URLSession identifier are also stable. They are collected in `AppIdentity`, separately from the public name, and guarded by regression tests. Existing installs therefore use the same sandbox, preferences, model files, archives, knowledge database, credentials, and transfer ledger. Do not replace these persisted identifiers as part of cosmetic branding changes.

The built-in folder is displayed simply as “Exports.” Its ID and capabilities are unchanged; user-connected folder names and bookmarks are not renamed. Historical incident notes retain the original app name where needed to describe the actual screenshot and logs.
