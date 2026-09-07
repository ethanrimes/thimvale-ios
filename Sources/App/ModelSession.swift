import Foundation
import Observation

/// Owns the lifetime of model weights, independently of conversations and KV state.
@MainActor @Observable final class ModelSession {
    enum State: Equatable { case unloaded, loading, ready, failed(String) }
    private(set) var state: State = .unloaded
    private(set) var model: URL?
    private(set) var isForeground: Bool
    @ObservationIgnored private let inference: any InferenceServing
    @ObservationIgnored private let idleTimeout: Duration
    @ObservationIgnored private var loadTask: Task<Void, Error>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var busy = false

    init(inference: any InferenceServing, idleTimeout: Duration = .seconds(300), isForeground: Bool = true) {
        self.inference = inference; self.idleTimeout = idleTimeout; self.isForeground = isForeground
    }
    deinit { loadTask?.cancel(); idleTask?.cancel(); inference.unload() }

    var label: String {
        switch state {
        case .unloaded: "Unloaded · loads when you send"
        case .loading: "Loading into memory…"
        case .ready: "In memory"
        case .failed: "Couldn't load model · tap to retry"
        }
    }
    func select(_ url: URL?, preload: Bool = true) {
        if model != url { release(); model = url }
        guard preload, isForeground, model != nil else { return }
        if state == .ready { touch(); return }
        startLoading()
    }
    func activate() { isForeground = true }
    func suspend() { isForeground = false; release() }
    func release() {
        request = UUID()
        loadTask?.cancel(); loadTask = nil
        idleTask?.cancel(); idleTask = nil
        inference.unload()
        state = .unloaded
    }
    func cancelLoading() { if state == .loading { release() } }
    func beginUse() { busy = true; idleTask?.cancel(); idleTask = nil }
    func endUse() { busy = false; touch() }
    func touch() {
        idleTask?.cancel(); idleTask = nil
        guard !busy, isForeground, state == .ready else { return }
        let delay = idleTimeout
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !self.busy, self.state == .ready else { return }
            self.release()
        }
    }
    func ensureReady() async throws {
        try Task.checkCancellation()
        guard isForeground else { throw CancellationError() }
        if state == .ready { return }
        startLoading()
        guard let task = loadTask else { throw PocketError.message("Choose a downloaded model first.") }
        let expected = request
        try await task.value
        try Task.checkCancellation()
        guard request == expected, state == .ready else { throw CancellationError() }
    }
    private func startLoading() {
        guard loadTask == nil, let model, isForeground else { return }
        state = .loading
        let expected = UUID(); request = expected
        let inference = inference
        loadTask = Task { [weak self] in
            do {
                try await inference.load(model: model)
                try Task.checkCancellation()
                guard let self, self.request == expected else { throw CancellationError() }
                self.state = .ready; self.loadTask = nil; self.touch()
            } catch {
                if let self, self.request == expected {
                    self.state = Task.isCancelled || error is CancellationError ? .unloaded : .failed(error.localizedDescription)
                    self.loadTask = nil
                }
                throw error
            }
        }
    }
}
