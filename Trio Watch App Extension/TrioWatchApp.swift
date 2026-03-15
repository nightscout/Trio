import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit

@main struct TrioWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            TrioMainWatchView()
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            switch newScenePhase {
            case .active:
                // App became active - schedule refresh and request fresh data
                WatchAppDelegate.scheduleBackgroundRefresh()
                WatchState.shared.requestWatchStateUpdate()
            case .background:
                Task {
                    await WatchLogger.shared.flushPersistedLogs()
                }
                // Schedule background refresh to keep complications updated
                WatchAppDelegate.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }
}

// MARK: - Watch App Delegate for Background Refresh

class WatchAppDelegate: NSObject, WKApplicationDelegate {

    /// Called when the app finishes launching
    func applicationDidFinishLaunching() {
        // Schedule background refresh immediately on launch
        Self.scheduleBackgroundRefresh()

        // Request fresh data from iPhone
        WatchState.shared.requestWatchStateUpdate()

        Task {
            await WatchLogger.shared.log("🚀 Watch app launched - scheduled background refresh")
        }
    }

    /// Schedule background refresh to run periodically
    static func scheduleBackgroundRefresh() {
        // Schedule refresh for 15 minutes from now
        // watchOS allows ~4 background refreshes per hour, so 15 min is realistic
        let refreshDate = Date().addingTimeInterval(15 * 60)

        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: refreshDate,
            userInfo: nil
        ) { error in
            if let error = error {
                Task {
                    await WatchLogger.shared.log("⚠️ Failed to schedule background refresh: \(error)")
                }
            } else {
                Task {
                    await WatchLogger.shared.log("✅ Scheduled background refresh for \(refreshDate)")
                }
            }
        }
    }

    /// Handle background refresh task
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                Task {
                    await WatchLogger.shared.log("🔄 Background refresh triggered")
                }

                // IMPORTANT: Access WatchState.shared FIRST to trigger WCSession activation
                // The session activation happens in WatchState's init
                let watchState = WatchState.shared

                // Give session a moment to activate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Check applicationContext for any pending complication data
                    // This data was sent by iPhone while the app was killed
                    if WCSession.default.activationState == .activated {
                        let context = WCSession.default.receivedApplicationContext
                        if context["complicationUpdate"] as? Bool == true {
                            Task {
                                await WatchLogger.shared.log("📥 Found complication data in applicationContext during background refresh")
                            }
                            // Update complication data from context
                            watchState.updateComplicationFromContext(context)
                        }
                    } else {
                        Task {
                            await WatchLogger.shared.log("⚠️ WCSession not activated during background refresh")
                        }
                    }

                    // Request fresh data from iPhone
                    watchState.requestWatchStateUpdate()

                    // Reload complications to show current data or staleness
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }

                // Schedule next refresh (do this immediately, not in the delayed block)
                Self.scheduleBackgroundRefresh()

                // Mark task complete after giving time for async work
                // Background tasks have ~15 seconds, our work takes ~1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    backgroundTask.setTaskCompletedWithSnapshot(false)
                }

            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
