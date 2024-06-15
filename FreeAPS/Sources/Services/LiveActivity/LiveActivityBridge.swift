import ActivityKit
import CoreData
import Foundation
import Swinject
import UIKit

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

@available(iOS 16.2, *) final class LiveActivityBridge: Injectable, ObservableObject
{
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var storage: FileStorage!

    private let activityAuthorizationInfo = ActivityAuthorizationInfo()
    @Published private(set) var systemEnabled: Bool

    private var settings: FreeAPSSettings {
        settingsManager.settings
    }

    var determination: DeterminationData?
    private var currentActivity: ActiveActivity?
    private var latestGlucose: GlucoseData?
    var glucoseFromPersistence: [GlucoseData]?

    let context = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        systemEnabled = activityAuthorizationInfo.areActivitiesEnabled
        injectServices(resolver)
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

            // Push the update to the Live Activity
            glucoseDidUpdate(glucoseFromPersistence ?? [])
        }
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
                glucoseDidUpdate(glucoseFromPersistence ?? [])
            }
        } else {
            Task {
                await self.endActivity()
            }
        }
    }

    /// attempts to present this live activity state, creating a new activity if none exists yet
    @MainActor private func pushUpdate(_ state: LiveActivityAttributes.ContentState) async {
//        // End all activities that are not the current one
        for unknownActivity in Activity<LiveActivityAttributes>.activities
            .filter({ self.currentActivity?.activity.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }

        if let currentActivity = currentActivity {
            if currentActivity.needsRecreation(), UIApplication.shared.applicationState == .active {
                await endActivity()
                await pushUpdate(state)
            } else {
                let content = ActivityContent(
                    state: state,
                    staleDate: min(state.date, Date.now).addingTimeInterval(360) // 6 minutes in seconds
                )
                await currentActivity.activity.update(content)
            }
        } else {
            do {
                // Create initial non-stale content
                let nonStaleContent = ActivityContent(
                    state: LiveActivityAttributes.ContentState(
                        bg: "--",
                        direction: nil,
                        change: "--",
                        date: Date.now,
                        chart: [],
                        chartDate: [],
                        rotationDegrees: 0,
                        highGlucose: 180,
                        lowGlucose: 70,
                        cob: 0,
                        iob: 0,
                        lockScreenView: "Simple",
                        unit: "--"
                    ),
                    staleDate: Date.now.addingTimeInterval(60)
                )

                // Request a new activity
                let activity = try Activity.request(
                    attributes: LiveActivityAttributes(startDate: Date.now),
                    content: nonStaleContent,
                    pushType: nil
                )
                currentActivity = ActiveActivity(activity: activity, startDate: Date.now)

                // Push the actual content
                await pushUpdate(state)
            } catch {
                print("Activity creation error: \(error)")
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
extension LiveActivityBridge {
    func glucoseDidUpdate(_ glucose: [GlucoseData]) {
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

        guard let bg = glucose.first else {
            return
        }

        if let determination = determination {
            let content = LiveActivityAttributes.ContentState(
                new: bg,
                prev: latestGlucose,
                mmol: settings.units == .mmolL,
                chart: glucose,
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
}
