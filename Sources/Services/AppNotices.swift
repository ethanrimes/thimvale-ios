import Foundation
import Observation
import UserNotifications

@MainActor @Observable final class ReviewPrompter {
    private var cadence = AppPaths.load(ReviewCadence.self, name: "review-cadence.json") ?? .init()
    var enabled = AppPaths.preferences.object(forKey: "reviewRequestsEnabled") as? Bool ?? true {
        didSet { AppPaths.preferences.set(enabled, forKey: "reviewRequestsEnabled") }
    }
    var alreadyReviewed = AppPaths.preferences.bool(forKey: "alreadyReviewed") {
        didSet { AppPaths.preferences.set(alreadyReviewed, forKey: "alreadyReviewed") }
    }
    static var isStoreBuild: Bool {
        #if DEBUG
        return false
        #else
        // TestFlight receipts are sandboxReceipt. Missing receipts and local
        // installations must not direct beta testers to a nonexistent listing.
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "receipt"
        #endif
    }
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6809304454?action=write-review")!
    func recordInteraction() { cadence.interactions += 1; try? AppPaths.save(cadence, as: "review-cadence.json") }
    func consumeOpportunity(now: Date = Date()) -> Bool {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard cadence.eligible(now: now, version: version, enabled: enabled, alreadyReviewed: alreadyReviewed, storeBuild: Self.isStoreBuild) else { return false }
        cadence.requested(now: now, version: version)
        try? AppPaths.save(cadence, as: "review-cadence.json")
        return true
    }
}

@MainActor @Observable final class PackNotifications {
    private(set) var enabled = AppPaths.preferences.bool(forKey: "packUpdateNotifications")
    private(set) var error: String?
    private(set) var authorizing = false
    var noticeCount = 0
    @ObservationIgnored private var seen = Set(AppPaths.preferences.stringArray(forKey: "noticedWikipediaEditions") ?? [])
    @ObservationIgnored private var sent = Set(AppPaths.preferences.stringArray(forKey: "notifiedWikipediaEditions") ?? [])
    @ObservationIgnored private var inFlight = Set<String>()

    func setEnabled(_ value: Bool) async {
        guard !authorizing else { return }
        error = nil
        if !value {
            enabled = false; AppPaths.preferences.set(false, forKey: "packUpdateNotifications")
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("wiki-update-") }.map(\.identifier))
            return
        }
        authorizing = true
        defer { authorizing = false }
        do {
            enabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            AppPaths.preferences.set(enabled, forKey: "packUpdateNotifications")
            if !enabled { error = "Notifications are off in iOS Settings. Updates still appear inside the app." }
        } catch { self.error = error.localizedDescription }
    }

    func discovered(_ updates: [WikipediaUpdate]) async {
        let editions = Set(updates.map { $0.pack.filename })
        let newNotices = editions.subtracting(seen)
        if !newNotices.isEmpty {
            noticeCount = updates.count
            seen.formUnion(newNotices)
            AppPaths.preferences.set(Array(seen).sorted(), forKey: "noticedWikipediaEditions")
        }
        if updates.isEmpty { noticeCount = 0 }
        let newAlerts = editions.subtracting(sent).subtracting(inFlight)
        guard enabled, !newAlerts.isEmpty else { return }
        inFlight.formUnion(newAlerts)
        defer { inFlight.subtract(newAlerts) }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard enabled, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Wikipedia updates available"
        content.body = newAlerts.count == 1 ? "A newer edition is ready to download. Your current pack still works offline." : "Newer editions of \(newAlerts.count) packs are ready to download."
        content.userInfo = ["destination": "wikipedia-updates"]
        // The notification contains no queries, source text, or private filenames.
        let request = UNNotificationRequest(identifier: "wiki-update-" + StableID.hash(newAlerts.sorted().joined(separator: ":")), content: content, trigger: nil)
        do {
            try await center.add(request)
            sent.formUnion(newAlerts)
            AppPaths.preferences.set(Array(sent).sorted(), forKey: "notifiedWikipediaEditions")
        } catch { self.error = error.localizedDescription }
    }
    func dismissNotice() { noticeCount = 0 }
}
