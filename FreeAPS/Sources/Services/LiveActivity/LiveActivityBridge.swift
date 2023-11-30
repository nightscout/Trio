import ActivityKit
import Foundation
import Swinject
import UIKit

extension LiveActivityAttributes.ContentState {
    static func formatGlucose(_ value: Int, mmol: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if mmol {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
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

        let formattedBG = Self.formatGlucose(glucose, mmol: mmol)

        let trentString: String?
        switch bg.direction {
        case .doubleUp,
             .singleUp,
             .tripleUp:
            trentString = "arrow.up"

        case .fortyFiveUp:
            trentString = "arrow.up.right"

        case .flat:
            trentString = "arrow.right"

        case .fortyFiveDown:
            trentString = "arrow.down.right"

        case .doubleDown,
             .singleDown,
             .tripleDown:
            trentString = "arrow.down"

        case .notComputable,
             Optional.none,
             .rateOutOfRange,
             .some(.none):
            trentString = nil
        }

        let change = prev?.glucose.map({ glucose - $0 })

        self.init(bg: formattedBG, trendSystemImage: trentString, change: change, date: bg.dateString)
    }
}

@available(iOS 16.2, *) private struct ActiveActivity {
    let activity: Activity<LiveActivityAttributes>
    let startDate: Date
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
            // just before app resigns active, show a new activity
            // only do this if there is no current activity or the current activity is older than 1h
            if self.settings.useLiveActivity {
                if (self.currentActivity?.startDate).map({ -$0.timeIntervalSinceNow >
                        TimeInterval(60 * 60) }) ?? true
                {
                    self.forceActivityUpdate()
                }
            } else {
                Task {
                    await self.endActivity()
                }
            }
        }
    }

    /// creates and tries to present a new activity update from the current GlucoseStorage values
    private func forceActivityUpdate() {
        glucoseDidUpdate(glucoseStorage.recent())
    }

    /// attempts to present this live activity state, creating a new activity if none exists yet
    private func pushUpdate(_ state: LiveActivityAttributes.ContentState) async {
        // hide duplicate/unknown activities
        for unknownActivity in Activity<LiveActivityAttributes>.activities
            .filter({ self.currentActivity?.activity.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }

        let content = ActivityContent(state: state, staleDate: state.date.addingTimeInterval(TimeInterval(6 * 60)))

        if let currentActivity {
            switch currentActivity.activity.activityState {
            case .dismissed,
                 .ended:
                // activity is no longer visible. End it and try to push the update again
                await endActivity()
                await pushUpdate(state)
            case .active,
                 .stale: await currentActivity.activity.update(content)
            @unknown default:
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
