import Foundation
import Security

enum AppPaths {
    // Simulator regression runs must never change the user's library or credentials.
    static var testSession: String? {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["THIMVALE_TEST_SESSION"].flatMap(UUID.init(uuidString:))?.uuidString
        #else
        return nil
        #endif
    }
    static let preferences: UserDefaults = testSession.flatMap { UserDefaults(suiteName: AppIdentity.bundleIdentifier + ".tests." + $0) } ?? .standard
    static var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let testSession { return support.appendingPathComponent("ThimvaleTests", isDirectory: true).appendingPathComponent(testSession, isDirectory: true) }
        return support.appendingPathComponent(AppIdentity.storageDirectory, isDirectory: true)
    }
    static var models: URL { root.appendingPathComponent("Models", isDirectory: true) }
    static var archives: URL { root.appendingPathComponent("Archives", isDirectory: true) }
    static var staging: URL { root.appendingPathComponent("Transfers", isDirectory: true) }
    static var exports: URL {
        if testSession != nil { return root.appendingPathComponent("Exports", isDirectory: true) }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports", isDirectory: true)
    }

    static func prepare() throws {
        for var directory in [root, models, archives, staging, exports] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        }
    }
    static func save<T: Encodable>(_ value: T, as name: String) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: root.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum Keychain {
    private static var service: String { AppIdentity.keychainService + (AppPaths.testSession.map { ".tests." + $0 } ?? "") }
    static func read(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PocketError.message("Could not save the key to the iPhone Keychain.") }
    }
}
