import SwiftUI
import UserNotifications

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var state: AppState?
    var pendingCompletion: (() -> Void)?
    var pendingWikipediaRoute = false
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let isUpdate = response.notification.request.content.userInfo["destination"] as? String == "wikipedia-updates"
        Task { @MainActor in
            if isUpdate {
                if let state { state.selectedTab = 2; state.showWikipediaUpdates = true }
                else { pendingWikipediaRoute = true }
            }
            completionHandler()
        }
    }
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
                            if delegate.pendingWikipediaRoute { state.selectedTab = 2; state.showWikipediaUpdates = true; delegate.pendingWikipediaRoute = false }
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
