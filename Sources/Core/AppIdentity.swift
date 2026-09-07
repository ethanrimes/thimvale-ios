import Foundation

enum AppIdentity {
    static let displayName = "Thimvale"
    static let repositoryURL = URL(string: "https://github.com/ethanrimes/thimvale-ios")!

    // The owner registered this bundle ID for TestFlight. It is a separate install
    // from the pre-release pocketmind bundle; there is no cross-sandbox migration.
    static let bundleIdentifier = "com.ethanrimes.thimvale"
    // Private names need not match branding. Keep these stable within this bundle.
    static let storageDirectory = "PocketMind"
    static let keychainService = "com.ethanrimes.pocketmind"
    static let downloadSessionIdentifier = "com.ethanrimes.pocketmind.downloads"
}
