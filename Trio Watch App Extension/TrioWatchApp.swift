import SwiftUI
import UserNotifications

@main struct TrioWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @WKApplicationDelegateAdaptor private var delegate: TrioWatchAppDelegate

    init() {
        _ = WatchState.shared
        // restores the watch's own link to the sensor
        _ = WatchCGMHost.shared
        WatchNotificationHandler.shared.configure()
        WatchLogger.shared.info(.lifecycle, "App launched")
    }

    var body: some Scene {
        WindowGroup {
            TrioMainWatchView()
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .background {
                WatchLogger.shared.info(.lifecycle, "App moved to background")
                WatchLogger.shared.didEnterBackground()
            } else if newScenePhase == .active {
                // looking at the watch is a wake that is not the sensor's own
                WatchCGMHost.shared.recheckAcquisition()
                // the watch's own reading may have aged out while the app was suspended
                WatchState.shared.refreshShownReading()
            }
        }
    }
}
