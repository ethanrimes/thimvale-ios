import Foundation

/// Local reminder eligibility, not knowledge of whether Apple showed a prompt
/// or whether a person submitted a review. No rating/sentiment gating.
struct ReviewCadence: Codable {
    var firstUse = Date()
    var interactions = 0
    var lastRequested: Date?
    var lastVersion: String?

    func eligible(now: Date, version: String, enabled: Bool, alreadyReviewed: Bool, storeBuild: Bool) -> Bool {
        guard storeBuild, enabled, !alreadyReviewed, interactions >= 5,
              now.timeIntervalSince(firstUse) >= 7 * 86_400, lastVersion != version else { return false }
        return lastRequested.map { now.timeIntervalSince($0) >= 120 * 86_400 } ?? true
    }
    mutating func requested(now: Date, version: String) { lastRequested = now; lastVersion = version }
}
