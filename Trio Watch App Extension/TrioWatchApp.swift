import SwiftUI
import UserNotifications

@main struct TrioWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _ = WatchState.shared
        WatchNotificationHandler.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            TrioMainWatchView()
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .background {
                Task {
                    await WatchLogger.shared.flushPersistedLogs()
                }
            } else if newScenePhase == .active {
                WatchState.shared.refreshIfNeeded()
            }
        }
    }
}
