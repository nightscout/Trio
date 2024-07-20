import ActivityKit
<<<<<<< HEAD
import CoreData
=======
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
import Foundation
import Swinject
import UIKit

<<<<<<< HEAD
=======
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

        let detailedState: LiveActivityAttributes.ContentAdditionalState?

        switch settings.lockScreenView {
        case .detailed:
            let chartBG = chart.map(\.glucose)

            let conversionFactor: Double = settings.units == .mmolL ? 18.0 : 1.0
            let convertedChartBG = chartBG.map { Double($0) / conversionFactor }

            let chartDate = chart.map(\.date)

            /// glucose limits from UI settings
            let highGlucose = settings.high / Decimal(conversionFactor)
            let lowGlucose = settings.low / Decimal(conversionFactor)

            let cob = suggestion.cob ?? 0
            let iob = suggestion.iob ?? 0

            detailedState = LiveActivityAttributes.ContentAdditionalState(
                chart: convertedChartBG,
                chartDate: chartDate,
                rotationDegrees: rotationDegrees,
                highGlucose: Double(highGlucose),
                lowGlucose: Double(lowGlucose),
                cob: cob,
                iob: iob
            )
        case .simple:
            detailedState = nil
        }

        self.init(
            bg: formattedBG,
            direction: trendString,
            change: change,
            date: bg.dateString,
            detailedViewState: detailedState,
            isInitialState: false
        )
    }
}

>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
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

<<<<<<< HEAD
@available(iOS 16.2, *) final class LiveActivityBridge: Injectable, ObservableObject
{
    @Injected() private var settingsManager: SettingsManager!
=======
@available(iOS 16.2, *) final class LiveActivityBridge: Injectable, ObservableObject {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var storage: FileStorage!

    private let activityAuthorizationInfo = ActivityAuthorizationInfo()
    @Published private(set) var systemEnabled: Bool

    private var settings: FreeAPSSettings {
        settingsManager.settings
    }

<<<<<<< HEAD
    var determination: DeterminationData?
    private var currentActivity: ActiveActivity?
    private var latestGlucose: GlucoseData?
    var glucoseFromPersistence: [GlucoseData]?
    var isOverridesActive: OverrideData?

    let context = CoreDataStack.shared.newTaskContext()
=======
    var suggestion: Suggestion? {
        storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
    }

    private var currentActivity: ActiveActivity?
    private var latestGlucose: BloodGlucose?
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133

    init(resolver: Resolver) {
        systemEnabled = activityAuthorizationInfo.areActivitiesEnabled
        injectServices(resolver)
<<<<<<< HEAD
        setupNotifications()
        monitorForLiveActivityAuthorizationChanges()
        setupGlucoseArray()
    }

    private func setupNotifications() {
        let notificationCenter = Foundation.NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleBatchInsert), name: .didPerformBatchInsert, object: nil)
        notificationCenter
            .addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
                self?.forceActivityUpdate()
            }
        notificationCenter
            .addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
                self?.forceActivityUpdate()
            }
    }

    @objc private func handleBatchInsert() {
        setupGlucoseArray()
    }

    private func setupGlucoseArray() {
        Task {
            // Fetch and map glucose to GlucoseData struct
            await fetchAndMapGlucose()

            // Fetch and map Determination to DeterminationData struct
            await fetchAndMapDetermination()

            // Fetch and map Override to OverrideData struct
            /// to show if there is an active Override
            await fetchAndMapOverride()

            // Push the update to the Live Activity
            glucoseDidUpdate(glucoseFromPersistence ?? [])
        }
=======
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
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
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
<<<<<<< HEAD
                glucoseDidUpdate(glucoseFromPersistence ?? [])
=======
                glucoseDidUpdate(glucoseStorage.recent())
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
            }
        } else {
            Task {
                await self.endActivity()
            }
        }
    }

    /// attempts to present this live activity state, creating a new activity if none exists yet
    @MainActor private func pushUpdate(_ state: LiveActivityAttributes.ContentState) async {
<<<<<<< HEAD
//        // End all activities that are not the current one
=======
        // hide duplicate/unknown activities
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
        for unknownActivity in Activity<LiveActivityAttributes>.activities
            .filter({ self.currentActivity?.activity.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }

<<<<<<< HEAD
        if let currentActivity = currentActivity {
            if currentActivity.needsRecreation(), UIApplication.shared.applicationState == .active {
=======
        if let currentActivity {
            if currentActivity.needsRecreation(), UIApplication.shared.applicationState == .active {
                // activity is no longer visible or old. End it and try to push the update again
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                await endActivity()
                await pushUpdate(state)
            } else {
                let content = ActivityContent(
                    state: state,
<<<<<<< HEAD
                    staleDate: min(state.date, Date.now).addingTimeInterval(360) // 6 minutes in seconds
=======
                    staleDate: min(state.date, Date.now).addingTimeInterval(TimeInterval(6 * 60))
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                )
                await currentActivity.activity.update(content)
            }
        } else {
            do {
<<<<<<< HEAD
                // Create initial non-stale content
                let nonStaleContent = ActivityContent(
=======
                // always push a non-stale content as the first update
                // pushing a stale content as the frst content results in the activity not being shown at all
                // apparently this initial state is also what is shown after the live activity expires (after 8h)
                let expired = ActivityContent(
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                    state: LiveActivityAttributes.ContentState(
                        bg: "--",
                        direction: nil,
                        change: "--",
                        date: Date.now,
<<<<<<< HEAD
                        chart: [],
                        chartDate: [],
                        rotationDegrees: 0,
                        highGlucose: 180,
                        lowGlucose: 70,
                        cob: 0,
                        iob: 0,
                        lockScreenView: "Simple",
                        unit: "--",
                        isOverrideActive: false
=======
                        detailedViewState: nil,
                        isInitialState: true
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                    ),
                    staleDate: Date.now.addingTimeInterval(60)
                )

<<<<<<< HEAD
                // Request a new activity
                let activity = try Activity.request(
                    attributes: LiveActivityAttributes(startDate: Date.now),
                    content: nonStaleContent,
=======
                let activity = try Activity.request(
                    attributes: LiveActivityAttributes(startDate: Date.now),
                    content: expired,
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                    pushType: nil
                )
                currentActivity = ActiveActivity(activity: activity, startDate: Date.now)

<<<<<<< HEAD
                // Push the actual content
                await pushUpdate(state)
            } catch {
                print("Activity creation error: \(error)")
=======
                // then show the actual content
                await pushUpdate(state)
            } catch {
                print("activity creation error: \(error)")
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
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
<<<<<<< HEAD
extension LiveActivityBridge {
    func glucoseDidUpdate(_ glucose: [GlucoseData]) {
=======
extension LiveActivityBridge: GlucoseObserver {
    func glucoseDidUpdate(_ glucose: [BloodGlucose]) {
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
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
<<<<<<< HEAD
            latestGlucose = glucose.dropFirst().first
        }
        defer {
            self.latestGlucose = glucose.first
        }

        guard let bg = glucose.first else {
            return
        }

        if let determination = determination {
            let content = LiveActivityAttributes.ContentState(
                new: bg,
                prev: latestGlucose,
                units: settings.units,
                chart: glucose,
                settings: settings,
                determination: determination,
                override: isOverridesActive
=======
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
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
            )

            if let content = content {
                Task {
                    await self.pushUpdate(content)
                }
            }
        }
    }
}
