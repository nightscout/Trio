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

    static func calculateChange(chart: [GlucoseStored]) -> String {
        guard chart.count > 2 else { return "" }
        let lastGlucose = chart.first?.glucose ?? 0
        let secondLastGlucose = chart.dropFirst().first?.glucose ?? 0
        let delta = lastGlucose - secondLastGlucose
        let deltaAsDecimal = Decimal(delta)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "  +"
        formatter.negativePrefix = "  -"
        return formatter.string(from: deltaAsDecimal as NSNumber) ?? "--"
    }

    init?(
        new bg: GlucoseStored,
        prev _: GlucoseStored?,
        mmol: Bool,
        chart: [GlucoseStored],
        settings: FreeAPSSettings,
        determination: OrefDetermination?
    ) {
        let glucose = bg.glucose
        let formattedBG = Self.formatGlucose(Int(glucose), mmol: mmol, forceSign: false)
        var rotationDegrees: Double = 0.0

        switch bg.direction {
        case "DoubleUp",
             "SingleUp",
             "TripleUp":
            rotationDegrees = -90
        case "FortyFiveUp":
            rotationDegrees = -45
        case "Flat":
            rotationDegrees = 0
        case "FortyFiveDown":
            rotationDegrees = 45
        case "DoubleDown",
             "SingleDown",
             "TripleDown":
            rotationDegrees = 90
        case "NONE",
             "NOT COMPUTABLE",
             "RATE OUT OF RANGE":
            rotationDegrees = 0
        default:
            rotationDegrees = 0
        }

        let trendString = bg.direction?.symbol as? String
        let change = Self.calculateChange(chart: chart)
        let chartBG = chart.map(\.glucose)
        let conversionFactor: Double = settings.units == .mmolL ? 18.0 : 1.0
        let convertedChartBG = chartBG.map { Double($0) / conversionFactor }
        let chartDate = chart.map(\.date)

        /// glucose limits from UI settings, not from notifications settings
        let highGlucose = settings.high / Decimal(conversionFactor)
        let lowGlucose = settings.low / Decimal(conversionFactor)
        let cob = determination?.cob ?? 0
        let iob = determination?.iob ?? 0
        let lockScreenView = settings.lockScreenView.displayName
        let unit = settings.units == .mmolL ? " mmol/L" : " mg/dL"

        self.init(
            bg: formattedBG,
            direction: trendString,
            change: change,
            date: bg.date ?? Date(),
            chart: convertedChartBG,
            chartDate: chartDate,
            rotationDegrees: rotationDegrees,
            highGlucose: Double(highGlucose),
            lowGlucose: Double(lowGlucose),
            cob: Decimal(cob),
            iob: iob as Decimal,
            lockScreenView: lockScreenView,
            unit: unit
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
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var storage: FileStorage!

    private let activityAuthorizationInfo = ActivityAuthorizationInfo()
    @Published private(set) var systemEnabled: Bool

    private var settings: FreeAPSSettings {
        settingsManager.settings
    }

    private var determination: OrefDetermination?
    private var currentActivity: ActiveActivity?
    private var latestGlucose: GlucoseStored?

    init(resolver: Resolver) {
        systemEnabled = activityAuthorizationInfo.areActivitiesEnabled
        injectServices(resolver)
        broadcaster.register(GlucoseStoredObserver.self, observer: self)

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
        determination = fetchDetermination()
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

    private func fetchDetermination() -> OrefDetermination {
        let context = CoreDataStack.shared.viewContext
        do {
            let determinations = try context.fetch(OrefDetermination.fetch(NSPredicate.enactedDetermination))
            debugPrint("LA Bridge: \(#function) \(DebuggingIdentifiers.succeeded) fetched determinations")
            guard let latestDetermination = determinations.first else { return OrefDetermination() }
            return latestDetermination
        } catch {
            debugPrint("LA Bridge: \(#function) \(DebuggingIdentifiers.failed) failed to fetch determinaions")
            return OrefDetermination()
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
                glucoseDidUpdate(fetchGlucose())
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
                        lockScreenView: "Simple",
                        unit: "--"
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
extension LiveActivityBridge: GlucoseStoredObserver {
    func glucoseDidUpdate(_ glucose: [GlucoseStored]) {
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
            latestGlucose = glucose.dropFirst().first
        }
        defer {
            self.latestGlucose = glucose.first
        }

        // fetch glucose for the last 6 hours for the LA chart from Core Data
        let fetchedGlucose = fetchGlucose()

        guard let bg = glucose.first else {
            return
        }

        if let determination = determination {
            let content = LiveActivityAttributes.ContentState(
                new: bg,
                prev: latestGlucose,
                mmol: settings.units == .mmolL,
                chart: fetchedGlucose,
                settings: settings,
                determination: determination
            )

            if let content = content {
                Task {
                    await self.pushUpdate(content)
                }
            }
        }
    }

    private func fetchGlucose() -> [GlucoseStored] {
        let context = CoreDataStack.shared.viewContext
        do {
            let fetchedGlucose = try context
                .fetch(GlucoseStored.fetch(NSPredicate.predicateForSixHoursAgo, ascending: false, fetchLimit: 72))
            debugPrint(
                "LA Bridge: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) fetched glucose"
            )

            return fetchedGlucose
        } catch {
            debugPrint(
                "LA Bridge: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to fetch glucose"
            )
            return []
        }
    }
}
