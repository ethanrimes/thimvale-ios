import Foundation

enum AppIdentity {
    static let displayName = "Thimvale"
    static let repositoryURL = URL(string: "https://github.com/ethanrimes/thimvale-ios")!

    // Persisted identity is intentionally independent of the public name. Changing
    // these would orphan an existing installation's library, keys, or transfers.
    static let bundleIdentifier = "com.ethanrimes.pocketmind"
    static let storageDirectory = "PocketMind"
    static let keychainService = "com.ethanrimes.pocketmind"
    static let downloadSessionIdentifier = "com.ethanrimes.pocketmind.downloads"
}
