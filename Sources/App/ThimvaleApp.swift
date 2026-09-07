import SwiftUI

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var state: AppState?
    var pendingCompletion: (() -> Void)?
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        if let state { state.downloads.backgroundCompletion = completionHandler }
        else { pendingCompletion = completionHandler }
    }
}

@main struct ThimvaleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state: AppState?
    @State private var startupError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let state {
                    RootView(state: state)
                        .onAppear {
                            delegate.state = state
                            if let completion = delegate.pendingCompletion { state.downloads.backgroundCompletion = completion; delegate.pendingCompletion = nil }
                        }
                } else if let startupError {
                    ContentUnavailableView("Couldn't open \(AppIdentity.displayName)", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError))
                } else { ProgressView("Opening your workspace…") }
            }
            .task {
                guard state == nil, startupError == nil else { return }
                do {
                    let initial = try AppState()
                    #if DEBUG && targetEnvironment(simulator)
                    try await initial.prepareUITestFixtures()
                    #endif
                    state = initial
                } catch { startupError = error.localizedDescription }
            }
        }
    }
}
