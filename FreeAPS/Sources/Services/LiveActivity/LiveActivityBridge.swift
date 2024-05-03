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

    init?(
        new bg: BloodGlucose,
        prev: BloodGlucose?,
        mmol: Bool,
        chart: [Readings],
        settings: FreeAPSSettings,
        suggestion: Suggestion
    ) {
        guard let glucose = bg.glucose else {
            return nil
        }

        let formattedBG = Self.formatGlucose(glucose, mmol: mmol, forceSign: false)

        var rotationDegrees: Double = 0.0

        switch bg.direction {
        case .doubleUp,
             .singleUp,
             .tripleUp:
            rotationDegrees = -90
        case .fortyFiveUp:
            rotationDegrees = -45
        case .flat:
            rotationDegrees = 0
        case .fortyFiveDown:
            rotationDegrees = 45
        case .doubleDown,
             .singleDown,
             .tripleDown:
            rotationDegrees = 90
        case .notComputable,
             Optional.none,
             .rateOutOfRange,
             .some(.none):
            rotationDegrees = 0
        }

        let trendString = bg.direction?.symbol

        let change = prev?.glucose.map({
            Self.formatGlucose(glucose - $0, mmol: mmol, forceSign: true)
        }) ?? ""

        let chartBG = chart.map(\.glucose)

        let conversionFactor: Double = settings.units == .mmolL ? 18.0 : 1.0
        let convertedChartBG = chartBG.map { Double($0) / conversionFactor }

        let chartDate = chart.map(\.date)

        /// glucose limits from UI settings
        let highGlucose = settings.high / Decimal(conversionFactor)
        let lowGlucose = settings.low / Decimal(conversionFactor)

        let cob = suggestion.cob ?? 0
        let iob = suggestion.iob ?? 0

        let lockScreenView = settings.lockScreenView.displayName

        self.init(
            bg: formattedBG,
            direction: trendString,
            change: change,
            date: bg.dateString,
            chart: convertedChartBG,
            chartDate: chartDate,
            rotationDegrees: rotationDegrees,
            highGlucose: Double(highGlucose),
            lowGlucose: Double(lowGlucose),
            cob: cob,
            iob: iob,
            lockScreenView: lockScreenView
        )
    }
}

@available(iOS 16.2, *) private struct ActiveActivity {
    let activity: Activity<LiveActivityAttributes>
    let startDate: Date

    func needsRecreation() -> Bool {
        switch activity.activityState {
        case .dismissed,
             .ended,
             .stale:
            return true
        case .active: break
        @unknown default:
            return true
        }

        return -startDate.timeIntervalSinceNow >
            TimeInterval(60 * 60)
    }
}

@available(iOS 16.2, *) final class LiveActivityBridge: Injectable, ObservableObject {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var storage: FileStorage!

    private let activityAuthorizationInfo = ActivityAuthorizationInfo()
    @Published private(set) var systemEnabled: Bool

    private var settings: FreeAPSSettings {
        settingsManager.settings
    }

    var suggestion: Suggestion? {
        storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
    }

    private var currentActivity: ActiveActivity?
    private var latestGlucose: BloodGlucose?

    init(resolver: Resolver) {
        systemEnabled = activityAuthorizationInfo.areActivitiesEnabled
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

        monitorForLiveActivityAuthorizationChanges()
    }

    private func monitorForLiveActivityAuthorizationChanges() {
        Task {
            for await activityState in activityAuthorizationInfo.activityEnablementUpdates {
                if activityState != systemEnabled {
                    await MainActor.run {
                        systemEnabled = activityState
                    }
                }
            }
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

        if let currentActivity {
            if currentActivity.needsRecreation(), UIApplication.shared.applicationState == .active {
                // activity is no longer visible or old. End it and try to push the update again
                await endActivity()
                await pushUpdate(state)
            } else {
                let content = ActivityContent(
                    state: state,
                    staleDate: min(state.date, Date.now).addingTimeInterval(TimeInterval(6 * 60))
                )
                await currentActivity.activity.update(content)
            }
        } else {
            do {
                // always push a non-stale content as the first update
                // pushing a stale content as the frst content results in the activity not being shown at all
                // we want it shown though even if it is iniially stale, as we expect new BG readings to become available soon, which should then be displayed
                let nonStale = ActivityContent(
                    state: LiveActivityAttributes.ContentState(
                        bg: "--",
                        direction: nil,
                        change: "--",
                        date: Date.now,
                        chart: [],
                        chartDate: [],
                        rotationDegrees: 0,
                        highGlucose: Double(180),
                        lowGlucose: Double(70),
                        cob: 0,
                        iob: 0,
                        lockScreenView: "Simple"
                    ),
                    staleDate: Date.now.addingTimeInterval(60)
                )

                let activity = try Activity.request(
                    attributes: LiveActivityAttributes(startDate: Date.now),
                    content: nonStale,
                    pushType: nil
                )
                currentActivity = ActiveActivity(activity: activity, startDate: Date.now)

                // then show the actual content
                await pushUpdate(state)
            } catch {
                print("activity creation error: \(error)")
            }
        }
    }

    /// ends all live activities immediateny
    private func endActivity() async {
        if let currentActivity {
            await currentActivity.activity.end(nil, dismissalPolicy: .immediate)
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
        guard settings.useLiveActivity else {
            if currentActivity != nil {
                Task {
                    await self.endActivity()
                }
            }
            return
        }

        // backfill latest glucose if contained in this update
        if glucose.count > 1 {
            latestGlucose = glucose[glucose.count - 2]
        }
        defer {
            self.latestGlucose = glucose.last
        }

        // fetch glucose for chart from Core Data
        let coreDataStorage = CoreDataStorage()
        let sixHoursAgo = Calendar.current.date(byAdding: .hour, value: -6, to: Date()) ?? Date()
        let fetchGlucose = coreDataStorage.fetchGlucose(interval: sixHoursAgo as NSDate)

        guard let bg = glucose.last else {
            return
        }

        if let suggestion = suggestion {
            let content = LiveActivityAttributes.ContentState(
                new: bg,
                prev: latestGlucose,
                mmol: settings.units == .mmolL,
                chart: fetchGlucose,
                settings: settings,
                suggestion: suggestion
            )

            if let content = content {
                Task {
                    await self.pushUpdate(content)
                }
            }
        }
    }
}
