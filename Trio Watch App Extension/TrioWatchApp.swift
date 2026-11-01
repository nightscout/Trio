import SwiftUI
import UserNotifications
import WatchKit

@main struct TrioWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let state = WatchState()

    init() {
        WatchNotificationHandler.shared.configure()
        WatchLogger.shared.info(.lifecycle, "App launched")
    }

    var body: some Scene {
        WindowGroup {
            TrioMainWatchView(state: state)
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .background {
                WatchLogger.shared.info(.lifecycle, "App moved to background")
                WatchLogger.shared.didEnterBackground()
                WatchBackgroundRefresh.schedule()
            }
        }
        .backgroundTask(.appRefresh) { _ in
            await WatchBackgroundRefresh.refresh(state)
        }
        .backgroundTask(.watchConnectivity) {
            await WatchBackgroundRefresh.settle(state)
        }
    }
}

@MainActor enum WatchBackgroundRefresh {
    private static let interval: TimeInterval = 15 * 60
    private static let settleTimeout: TimeInterval = 5
    private static let settlePoll: TimeInterval = 0.25

    static func schedule() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: interval),
            userInfo: nil
        ) { error in
            if let error = error {
                WatchLogger.shared.warning(.lifecycle, "Background refresh scheduling failed", error: error)
            }
        }
    }

    static func refresh(_ state: WatchState) async {
        schedule()
        await settle(state)
        state.ingestReceivedApplicationContext()
        await settle(state)
    }

    static func settle(_ state: WatchState) async {
        let deadline = Date(timeIntervalSinceNow: settleTimeout)
        repeat {
            do {
                try await Task.sleep(for: .seconds(settlePoll))
            } catch {
                return
            }
        } while state.isAwaitingDelivery && Date() < deadline
    }
}
