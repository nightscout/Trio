import ActivityKit
import Foundation
import Swinject
import UIKit

extension LiveActivityAttributes.ContentState {
    static func formatGlucose(_ value: Int, mmol: Bool, forceSign: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if mmol {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        if forceSign {
            formatter.positivePrefix = formatter.plusSign
        }
        formatter.roundingMode = .halfUp

        return formatter
            .string(from: mmol ? value.asMmolL as NSNumber : NSNumber(value: value))!
    }

    init?(new bg: BloodGlucose, prev: BloodGlucose?, mmol: Bool) {
        guard let glucose = bg.glucose,
              bg.dateString.timeIntervalSinceNow > -TimeInterval(minutes: 6)
        else {
            return nil
        }

        let formattedBG = Self.formatGlucose(glucose, mmol: mmol, forceSign: false)

        let trendString: String?
        switch bg.direction {
        case .doubleUp,
             .singleUp,
             .tripleUp:
            trendString = "arrow.up"

        case .fortyFiveUp:
            trendString = "arrow.up.right"

        case .flat:
            trendString = "arrow.right"

        case .fortyFiveDown:
            trendString = "arrow.down.right"

        case .doubleDown,
             .singleDown,
             .tripleDown:
            trendString = "arrow.down"

        case .notComputable,
             Optional.none,
             .rateOutOfRange,
             .some(.none):
            trendString = nil
        }

        let change = prev?.glucose.map({
            Self.formatGlucose(glucose - $0, mmol: mmol, forceSign: true)
        }) ?? ""

        self.init(bg: formattedBG, trendSystemImage: trendString, change: change, date: bg.dateString)
    }
}

@available(iOS 16.2, *) private struct ActiveActivity {
    let activity: Activity<LiveActivityAttributes>
    let startDate: Date

    func needsRecreation() -> Bool {
        switch activity.activityState {
        case .dismissed,
             .ended:
            return true
        case .active,
             .stale: break
        @unknown default:
            return true
        }

        return -startDate.timeIntervalSinceNow >
            TimeInterval(60 * 60)
    }
}

@available(iOS 16.2, *) final class LiveActivityBridge: Injectable {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var broadcaster: Broadcaster!

    private var settings: FreeAPSSettings {
        settingsManager.settings
    }

    private var currentActivity: ActiveActivity?
    private var latestGlucose: BloodGlucose?

    init(resolver: Resolver) {
        injectServices(resolver)
        broadcaster.register(GlucoseObserver.self, observer: self)

        Foundation.NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            self.forceActivityUpdate()
        }

        Foundation.NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { _ in
            self.forceActivityUpdate()
        }
    }

    /// creates and tries to present a new activity update from the current GlucoseStorage values if live activities are enabled in settings
    /// Ends existing live activities if live activities are not enabled in settings
    private func forceActivityUpdate() {
        // just before app resigns active, show a new activity
        // only do this if there is no current activity or the current activity is older than 1h
        if settings.useLiveActivity {
            if currentActivity?.needsRecreation() ?? true
            {
                glucoseDidUpdate(glucoseStorage.recent())
            }
        } else {
            Task {
                await self.endActivity()
            }
        }
    }

    /// attempts to present this live activity state, creating a new activity if none exists yet
    @MainActor private func pushUpdate(_ state: LiveActivityAttributes.ContentState) async {
        // hide duplicate/unknown activities
        for unknownActivity in Activity<LiveActivityAttributes>.activities
            .filter({ self.currentActivity?.activity.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }

        let content = ActivityContent(state: state, staleDate: state.date.addingTimeInterval(TimeInterval(6 * 60)))

        if let currentActivity {
            if currentActivity.needsRecreation(), UIApplication.shared.applicationState == .active {
                // activity is no longer visible or old. End it and try to push the update again
                await endActivity()
                await pushUpdate(state)
            } else {
                await currentActivity.activity.update(content)
            }
        } else {
            do {
                let activity = try Activity.request(
                    attributes: LiveActivityAttributes(startDate: Date.now),
                    content: content,
                    pushType: nil
                )
                currentActivity = ActiveActivity(activity: activity, startDate: Date.now)
            } catch {
                print("activity creation error: \(error)")
            }
        }
    }

    /// ends all live activities immediateny
    private func endActivity() async {
        if let currentActivity {
            await currentActivity.activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            self.currentActivity = nil
        }

        // end any other activities
        for unknownActivity in Activity<LiveActivityAttributes>.activities {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

@available(iOS 16.2, *)
extension LiveActivityBridge: GlucoseObserver {
    func glucoseDidUpdate(_ glucose: [BloodGlucose]) {
        // backfill latest glucose if contained in this update
        if glucose.count > 1 {
            latestGlucose = glucose[glucose.count - 2]
        }
        defer {
            self.latestGlucose = glucose.last
        }

        guard let bg = glucose.last, let content = LiveActivityAttributes.ContentState(
            new: bg,
            prev: latestGlucose,
            mmol: settings.units == .mmolL
        ) else {
            // no bg or value stale. Don't update the activity if there already is one, just let it turn stale so that it can still be used once current bg is available again
            return
        }

        Task {
            await self.pushUpdate(content)
        }
    }
}
