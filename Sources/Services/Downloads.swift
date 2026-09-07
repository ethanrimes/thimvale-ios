import Foundation
import Observation

struct DownloadJob: Codable, Identifiable {
    enum Kind: String, Codable { case model, wikipedia }
    enum State: String, Codable { case downloading, paused, validating, ready, failed }
    var id: String
    var title: String
    var url: URL
    var kind: Kind
    var filename: String
    var expectedBytes: Int64
    var sha256: String?
    var model: ModelEntry?
    var received: Int64 = 0
    var state: State = .downloading
    var error: String?
    var progress: Double { expectedBytes > 0 ? min(1, Double(received) / Double(expectedBytes)) : 0 }
    var destination: URL { (kind == .model ? AppPaths.models : AppPaths.archives).appendingPathComponent(filename) }
}

@MainActor @Observable final class DownloadCenter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var jobs: [DownloadJob] = []
    var onReady: ((DownloadJob) -> Void)?
    var onError: ((String) -> Void)?
    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private let ledger: String
    @ObservationIgnored var backgroundCompletion: (() -> Void)?

    init(identifier: String = AppIdentity.downloadSessionIdentifier, ledger: String = "downloads.json") {
        self.ledger = ledger
        super.init()
        jobs = AppPaths.load([DownloadJob].self, name: ledger) ?? []
        let config: URLSessionConfiguration
        #if targetEnvironment(simulator)
        // Simulator runtimes may not provide nsurlsessiond. Exercise the same transfer
        // delegate and durable ledger with a foreground session on the simulator.
        config = .default
        #else
        config = .background(withIdentifier: identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        #endif
        config.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session.getAllTasks { [weak self] pending in
            Task { @MainActor in
                guard let self else { return }
                for task in pending {
                    if let id = task.taskDescription, let task = task as? URLSessionDownloadTask { self.tasks[id] = task }
                }
                for i in self.jobs.indices where self.jobs[i].state == .downloading || self.jobs[i].state == .validating {
                    if self.tasks[self.jobs[i].id] == nil {
                        let id = self.jobs[i].id
                        let staged = AppPaths.staging.appendingPathComponent(id + ".download")
                        if FileManager.default.fileExists(atPath: staged.path) {
                            self.jobs[i].state = .validating
                            Task { await self.finish(id, staged: staged) }
                        } else {
                            self.jobs[i].state = .paused
                            self.jobs[i].error = "Tap Resume to continue this transfer."
                        }
                    }
                }
                self.persist()
            }
        }
    }
    func start(_ job: DownloadJob) throws {
        guard !jobs.contains(where: { $0.id == job.id && $0.state != .failed && $0.state != .paused }) else { return }
        let capacity = try AppPaths.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard job.expectedBytes > 0, capacity > job.expectedBytes + 300_000_000 else { throw PocketError.message("There isn't enough free storage for this download, or its size could not be verified.") }
        jobs.removeAll { $0.id == job.id }
        jobs.append(job)
        resume(job.id)
    }
    func resume(_ id: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), tasks[id] == nil else { return }
        let staged = AppPaths.staging.appendingPathComponent(id + ".download")
        if FileManager.default.fileExists(atPath: staged.path) {
            jobs[index].state = .validating
            Task { await finish(id, staged: staged) }
            return
        }
        jobs[index].state = .downloading; jobs[index].error = nil
        let resumeURL = AppPaths.staging.appendingPathComponent(id + ".resume")
        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resumeURL) { task = session.downloadTask(withResumeData: data) }
        else {
            var request = URLRequest(url: jobs[index].url)
            request.allowsCellularAccess = AppPaths.preferences.bool(forKey: "cellularDownloads")
            if jobs[index].url.host == "huggingface.co", !Keychain.read("huggingface").isEmpty {
                request.setValue("Bearer " + Keychain.read("huggingface"), forHTTPHeaderField: "Authorization")
            }
            task = session.downloadTask(with: request)
        }
        task.taskDescription = id
        tasks[id] = task
        task.resume()
        persist()
    }
    func pause(_ id: String) {
        guard let task = tasks[id] else { return }
        if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index].state = .paused }
        task.cancel { data in
            if let data { try? data.write(to: AppPaths.staging.appendingPathComponent(id + ".resume"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        }
        persist()
    }
    func forget(_ id: String) {
        guard tasks[id] == nil else { return }
        jobs.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: AppPaths.staging.appendingPathComponent(id + ".resume"))
        try? FileManager.default.removeItem(at: AppPaths.staging.appendingPathComponent(id + ".download"))
        persist()
    }
    private func persist() {
        do { try AppPaths.save(jobs, as: ledger) }
        catch { onError?(error.localizedDescription) }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in
            guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[i].received = totalBytesWritten
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let staged = AppPaths.staging.appendingPathComponent(id + ".download")
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw PocketError.message("The server rejected the download. Check access, license terms, and the URL.") }
            if FileManager.default.fileExists(atPath: staged.path) { try FileManager.default.removeItem(at: staged) }
            try FileManager.default.moveItem(at: location, to: staged)
            Task { @MainActor in await finish(id, staged: staged) }
        } catch { Task { @MainActor in fail(id, error: error) } }
    }
    private func finish(_ id: String, staged: URL) async {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].state = .validating
        let job = jobs[i]
        persist()
        do {
            try await Task.detached(priority: .utility) {
                try FileValidation.check(staged, magic: job.kind == .model ? [0x47, 0x47, 0x55, 0x46] : [0x5a, 0x49, 0x4d, 0x04], expectedBytes: job.expectedBytes)
                if let digest = job.sha256, try FileValidation.sha256(staged) != digest.lowercased() { throw PocketError.message("Checksum verification failed. The downloaded file was not installed.") }
            }.value
            guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
            guard !FileManager.default.fileExists(atPath: job.destination.path) else { throw PocketError.message("This file is already installed.") }
            try FileManager.default.moveItem(at: staged, to: job.destination)
            try? FileManager.default.removeItem(at: AppPaths.staging.appendingPathComponent(id + ".resume"))
            jobs[index].state = .ready
            jobs[index].received = job.expectedBytes
            persist()
            onReady?(jobs[index])
        } catch {
            // A rejected staging file must not be retried as though it were a complete valid transfer.
            try? FileManager.default.removeItem(at: staged)
            try? FileManager.default.removeItem(at: AppPaths.staging.appendingPathComponent(id + ".resume"))
            fail(id, error: error)
        }
    }
    private func fail(_ id: String, error: Error) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].state = .failed; jobs[i].error = error.localizedDescription }
        persist()
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        Task { @MainActor in
            tasks[id] = nil
            guard let error else { return }
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                try? data.write(to: AppPaths.staging.appendingPathComponent(id + ".resume"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            if jobs.first(where: { $0.id == id })?.state != .paused { fail(id, error: error) }
        }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in backgroundCompletion?(); backgroundCompletion = nil }
    }
}
