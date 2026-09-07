import Foundation
import Network
import Observation

struct WikipediaEdition: Equatable, Sendable {
    let series: String
    let month: String

    static func parse(_ filename: String) -> WikipediaEdition? {
        let pattern = try! NSRegularExpression(pattern: "^(wikipedia_en_[a-z0-9_]+_(?:mini|nopic|maxi))_([0-9]{4}-(?:0[1-9]|1[0-2]))\\.zim$")
        guard let match = pattern.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
              let series = Range(match.range(at: 1), in: filename), let month = Range(match.range(at: 2), in: filename) else { return nil }
        return .init(series: String(filename[series]), month: String(filename[month]))
    }

    /// Retain old editions on disk, but avoid mixing dated versions in Q&A.
    static func preferredFiles(_ files: [String]) -> [String] {
        var newest: [String: String] = [:]
        var unversioned: [String] = []
        for file in files {
            guard let edition = parse(file) else { unversioned.append(file); continue }
            if let previous = newest[edition.series], let old = parse(previous), old.month >= edition.month { continue }
            newest[edition.series] = file
        }
        return (unversioned + Array(newest.values)).sorted()
    }
}

struct WikipediaUpdate: Identifiable {
    let currentFilename: String
    let pack: WikiPack
    var id: String { currentFilename }
}

@MainActor @Observable final class WikipediaUpdates {
    private(set) var catalog: [WikiPack] = []
    private(set) var installed: [String] = []
    private(set) var lastChecked: Date?
    private(set) var checking = false
    private(set) var error: String?
    private(set) var online = false
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private let persistCache: Bool
    @ObservationIgnored private let fetch: @Sendable () async throws -> [WikiPack]
    private struct Cache: Codable { let packs: [WikiPack]; let checked: Date }

    init(persistCache: Bool = true, fetch: @escaping @Sendable () async throws -> [WikiPack] = { try await WikipediaCatalog.fetch(includePictures: true) }) {
        self.persistCache = persistCache; self.fetch = fetch
        if persistCache, let cache = AppPaths.load(Cache.self, name: "wikipedia-update-catalog.json") {
            catalog = cache.packs; lastChecked = cache.checked
        }
    }
    deinit { monitor?.cancel() }

    var eligibleFiles: [String] { WikipediaEdition.preferredFiles(installed).filter { WikipediaEdition.parse($0) != nil } }
    var available: [WikipediaUpdate] {
        eligibleFiles.compactMap { file in
            guard let current = WikipediaEdition.parse(file) else { return nil }
            let candidates = catalog.filter { pack in
                guard let edition = WikipediaEdition.parse(pack.filename) else { return false }
                return edition.series == current.series && edition.month > current.month && !installed.contains(pack.filename)
            }
            guard let newest = candidates.max(by: { $0.filename < $1.filename }) else { return nil }
            return WikipediaUpdate(currentFilename: file, pack: newest)
        }
    }

    func setInstalled(_ files: [String]) { installed = files; scheduleCheck() }
    func setForeground(_ active: Bool, monitorNetwork: Bool = true) {
        foreground = active
        if monitorNetwork, monitor == nil {
            let path = NWPathMonitor()
            path.pathUpdateHandler = { [weak self] value in
                let connected = value.status == .satisfied
                Task { @MainActor [weak self] in self?.networkChanged(online: connected) }
            }
            path.start(queue: DispatchQueue(label: "Thimvale.WikipediaConnectivity"))
            monitor = path
        }
        if active { scheduleCheck() }
    }
    func networkChanged(online: Bool) {
        let reconnected = !self.online && online
        self.online = online
        if reconnected { scheduleCheck(reconnected: true) }
    }
    private func scheduleCheck(reconnected: Bool = false) {
        guard foreground, online, !eligibleFiles.isEmpty, !checking else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        if !reconnected, let lastChecked, Date().timeIntervalSince(lastChecked) < 6 * 60 * 60 { return }
        Task { await checkNow() }
    }
    func checkNow() async {
        guard !checking, !eligibleFiles.isEmpty else { return }
        checking = true; error = nil; lastAttempt = Date()
        defer { checking = false }
        do {
            let packs = try await fetch()
            try Task.checkCancellation()
            catalog = packs; lastChecked = Date()
            if persistCache { try AppPaths.save(Cache(packs: packs, checked: lastChecked!), as: "wikipedia-update-catalog.json") }
        } catch is CancellationError {}
        catch { self.error = "Couldn't check for updates. Your downloaded packs still work offline. \(error.localizedDescription)" }
    }
}
