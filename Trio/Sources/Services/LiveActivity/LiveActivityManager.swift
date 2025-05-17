import ActivityKit
import Combine
import CoreData
import Foundation
import Swinject
import UIKit

@available(iOS 16.2, *) private struct ActiveActivity {
    let activity: Activity<LiveActivityAttributes>
    let startDate: Date

    /// Determines if the current activity needs to be recreated.
    ///
    /// - Returns: `true` if the activity is dismissed, ended, stale, or has been active for more than 60 minutes; otherwise, `false`.
    func needsRecreation() -> Bool {
        switch activity.activityState {
        case .dismissed,
             .ended,
             .stale:
            return true
        case .active:
            break
        @unknown default:
            return true
        }
        return -startDate.timeIntervalSinceNow > TimeInterval(60 * 60)
    }
}

/// A service managing live activity updates and state management.
///
/// This class handles the creation, update, and termination of live activities based on various data sources
/// (e.g. Core Data notifications, glucose updates, settings changes). It integrates with system notifications,
/// dependency injection, and user defaults to ensure that the live activity reflects the current app state.
///
/// Additionally, it supports a restart functionality (via `restartActivityFromLiveActivityIntent()`)
/// via iOS shortcuts, similar to other iOS apps like xDrip4iOS or Sweet Dreams.
@available(iOS 16.2, *)
final class LiveActivityManager: Injectable, ObservableObject, SettingsObserver {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var storage: FileStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!

    private let activityAuthorizationInfo = ActivityAuthorizationInfo()
    /// Indicates whether system live activities are enabled.
    @Published private(set) var systemEnabled: Bool

    /// Returns the current Trio settings.
    private var settings: TrioSettings {
        settingsManager.settings
    }

    /// Determination data used to update live activity state.
    var determination: DeterminationData?
    /// The current active live activity.
    private var currentActivity: ActiveActivity?
    /// The most recent glucose reading.
    private var latestGlucose: GlucoseData?
    /// Array of glucose readings fetched from persistent storage.
    var glucoseFromPersistence: [GlucoseData]?
    /// The current override data (if any).
    var override: OverrideData?
    /// The widget items displayed within the live activity.
    var widgetItems: [LiveActivityAttributes.LiveActivityItem]?

    /// A Core Data task context.
    let context = CoreDataStack.shared.newTaskContext()

    /// A dispatch queue for handling Core Data change notifications.
    private let queue = DispatchQueue(label: "LiveActivityBridge.queue", qos: .userInitiated)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    /// Initializes a new instance of `LiveActivityBridge` and sets up observers, subscribers, and notifications.
    ///
    /// - Parameter resolver: The dependency injection resolver.
    init(resolver: Resolver) {
        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        systemEnabled = activityAuthorizationInfo.areActivitiesEnabled
        injectServices(resolver)
        setupNotifications()
        registerSubscribers()
        registerHandler()
        monitorForLiveActivityAuthorizationChanges()
        setupGlucoseArray()
        broadcaster.register(SettingsObserver.self, observer: self)
    }

    /// Sets up application notifications that trigger live activity updates when the app state changes.
    private func setupNotifications() {
        let notificationCenter = Foundation.NotificationCenter.default
        notificationCenter
            .addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.forceActivityUpdate()
                }
            }
        notificationCenter
            .addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.forceActivityUpdate()
                }
            }
        notificationCenter.addObserver(
            self,
            selector: #selector(handleLiveActivityOrderChange),
            name: .liveActivityOrderDidChange,
            object: nil
        )
    }

    /// Called when the app settings change.
    ///
    /// This method triggers an update to the live activity content state based on the new settings.
    /// - Parameter _: The updated `TrioSettings`.
    func settingsDidChange(_: TrioSettings) {
        Task {
            await updateContentState(determination)
        }
    }

    /// Registers handlers for Core Data changes related to overrides, glucose readings, and determinations.
    private func registerHandler() {
        coreDataPublisher?.filteredByEntityName("OverrideStored").sink { [weak self] _ in
            guard let self = self else { return }
            self.overridesDidUpdate()
        }.store(in: &subscriptions)

        coreDataPublisher?.filteredByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            self.setupGlucoseArray()
        }.store(in: &subscriptions)

        coreDataPublisher?.filteredByEntityName("OrefDetermination")
            .debounce(for: .seconds(2), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.cobOrIobDidUpdate()
            }.store(in: &subscriptions)
    }

    /// Registers subscribers for updates from the glucose storage.
    private func registerSubscribers() {
        glucoseStorage.updatePublisher
            .receive(on: queue)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.setupGlucoseArray()
            }
            .store(in: &subscriptions)
    }

    /// Fetches and maps new determination data and updates the live activity content state.
    private func cobOrIobDidUpdate() {
        Task { @MainActor in
            do {
                self.determination = try await fetchAndMapDetermination()
                if let determination = determination {
                    await self.updateContentState(determination)
                }
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) failed to fetch and map determination: \(error)"
                )
            }
        }
    }

    /// Fetches and maps override data and updates the live activity content state.
    private func overridesDidUpdate() {
        Task { @MainActor in
            do {
                self.override = try await fetchAndMapOverride()
                if let determination = determination {
                    await self.updateContentState(determination)
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch and map override: \(error)")
            }
        }
    }

    /// Handles changes to the live activity order.
    ///
    /// Loads widget items from user defaults and triggers an update to the live activity order.
    @objc private func handleLiveActivityOrderChange() {
        Task {
            self.widgetItems = UserDefaults.standard.loadLiveActivityOrderFromUserDefaults() ?? LiveActivityAttributes
                .LiveActivityItem.defaultItems
            await self.updateLiveActivityOrder()
        }
    }

    /// Updates the live activity content state based on new determination or override data.
    ///
    /// - Parameter update: An object representing new `DeterminationData` or `OverrideData`.
    @MainActor private func updateContentState<T>(_ update: T) async {
        guard let latestGlucose = latestGlucose else {
            return
        }
        var content: LiveActivityAttributes.ContentState?

        widgetItems = UserDefaults.standard.loadLiveActivityOrderFromUserDefaults() ?? LiveActivityAttributes
            .LiveActivityItem.defaultItems

        if let determination = update as? DeterminationData {
            content = LiveActivityAttributes.ContentState(
                new: latestGlucose,
                prev: latestGlucose,
                units: settings.units,
                chart: glucoseFromPersistence ?? [],
                settings: settings,
                determination: determination,
                override: override,
                widgetItems: widgetItems
            )
        } else if let override = update as? OverrideData {
            content = LiveActivityAttributes.ContentState(
                new: latestGlucose,
                prev: latestGlucose,
                units: settings.units,
                chart: glucoseFromPersistence ?? [],
                settings: settings,
                determination: determination,
                override: override,
                widgetItems: widgetItems
            )
        }

        if let content = content {
            await pushUpdate(content)
        }
    }

    /// Triggers an update of the live activity order.
    ///
    /// This method refreshes the activity's content state to reflect any changes in the widget order.
    @MainActor private func updateLiveActivityOrder() async {
        Task {
            await updateContentState(determination)
        }
    }

    /// Sets up the array of glucose data from persistent storage and triggers an update to the live activity.
    private func setupGlucoseArray() {
        Task { @MainActor in
            do {
                self.glucoseFromPersistence = try await fetchAndMapGlucose()
                glucoseDidUpdate(glucoseFromPersistence ?? [])
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch glucose with error: \(error)")
            }
        }
    }

    /// Monitors live activity authorization changes and updates the `systemEnabled` flag.
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

    /// Forces an update to the live activity.
    ///
    /// If live activities are enabled and the current activity requires recreation, this method triggers a new glucose update.
    /// Otherwise, it ends the current live activity.
    @MainActor private func forceActivityUpdate() {
        if settings.useLiveActivity {
            if currentActivity?.needsRecreation() ?? true {
                glucoseDidUpdate(glucoseFromPersistence ?? [])
            }
        } else {
            Task {
                await self.endActivity()
            }
        }
    }

    /// Pushes an update to the live activity with the specified content state.
    ///
    /// If an existing activity requires recreation or is outdated, this method ends it and starts a new one.
    /// Otherwise, it updates the current live activity.
    ///
    /// - Parameter state: The new content state to push to the live activity.
    @MainActor private func pushUpdate(_ state: LiveActivityAttributes.ContentState) async {
        // End all unknown activities except the current one
        for unknownActivity in Activity<LiveActivityAttributes>.activities
            .filter({ self.currentActivity?.activity.id != $0.id })
        {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }

        // Defensive: capture the current activity at function start
        let activityAtStart = currentActivity

        if let currentActivity = activityAtStart {
            if currentActivity.needsRecreation(), UIApplication.shared.applicationState == .active {
                debug(.default, "[LiveActivityManager] Ending current activity for recreation: \(currentActivity.activity.id)")
                await endActivity()
                // After endActivity(), currentActivity is guaranteed to be nil
                // No recursive task, but explicitly restart
                if self.currentActivity == nil {
                    debug(.default, "[LiveActivityManager] Re-pushing update after recreation.")
                    await pushUpdate(state)
                } else {
                    debug(.default, "[LiveActivityManager] Warning: currentActivity was not nil after endActivity!")
                }
                return
            } else {
                let content = ActivityContent(
                    state: state,
                    staleDate: min(state.date ?? Date.now, Date.now).addingTimeInterval(360)
                )
                // Before the update, check if currentActivity is still valid
                if let stillCurrent = self.currentActivity, stillCurrent.activity.id == currentActivity.activity.id {
                    debug(.default, "[LiveActivityManager] Updating current activity: \(stillCurrent.activity.id)")
                    await stillCurrent.activity.update(content)
                } else {
                    debug(.default, "[LiveActivityManager] Skipped update: currentActivity changed during pushUpdate.")
                }
            }
        } else {
            // ... Activity is newly created ...
            do {
                let expired = ActivityContent(
                    state: LiveActivityAttributes
                        .ContentState(
                            unit: settings.units.rawValue,
                            bg: "--",
                            direction: nil,
                            change: "--",
                            date: Date.now,
                            highGlucose: settings.high,
                            lowGlucose: settings.low,
                            target: determination?.target ?? 100 as Decimal,
                            glucoseColorScheme: settings.glucoseColorScheme.rawValue,
                            detailedViewState: nil,
                            isInitialState: true
                        ),
                    staleDate: Date.now.addingTimeInterval(60)
                )

                let activity = try Activity.request(
                    attributes: LiveActivityAttributes(startDate: Date.now),
                    content: expired,
                    pushType: nil
                )
                currentActivity = ActiveActivity(activity: activity, startDate: Date.now)
                debug(.default, "[LiveActivityManager] Created new activity: \(activity.id)")
                await pushUpdate(state)
            } catch {
                debug(
                    .default,
                    "\(#file): Error creating new activity: \(error)"
                )
            }
        }
    }

    /// Ends the current live activity and ensures that all unknown activities are terminated.
    private func endActivity() async {
        debug(.default, "Ending all live activities...")

        if let currentActivity {
            debug(.default, "Ending current activity: \(currentActivity.activity.id)")
            await currentActivity.activity.end(nil, dismissalPolicy: .immediate)
            self.currentActivity = nil
        }

        for activity in Activity<LiveActivityAttributes>.activities {
            debug(.default, "Ending lingering activity: \(activity.id)")
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        for unknownActivity in Activity<LiveActivityAttributes>.activities {
            debug(.default, "Ending unknown activity: \(unknownActivity.id)")
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }

        debug(.default, "All live activities ended.")
    }

    /// Restarts the live activity from a Live Activity Intent.
    ///
    /// This method mimics xdrip's `restartActivityFromLiveActivityIntent()` behavior by verifying that a valid content state exists,
    /// ending the current live activity, and starting a new one using the current state.
    @MainActor func restartActivityFromLiveActivityIntent() async {
        guard let latestGlucose = latestGlucose,
              let determination = determination
        else {
            debug(.default, "Cannot restart live activity because required persistent state is not available. Fetching data...")
            return
        }

        guard let contentState = LiveActivityAttributes.ContentState(
            new: latestGlucose,
            prev: latestGlucose,
            units: settings.units,
            chart: glucoseFromPersistence ?? [],
            settings: settings,
            determination: determination,
            override: override,
            widgetItems: widgetItems
        ) else {
            debug(.default, "Cannot restart live activity because content state cannot be created")
            return
        }

        await endActivity()

        while (currentActivity != nil && currentActivity!.activity.activityState != .ended) || Activity<LiveActivityAttributes>
            .activities.contains(where: { $0.activityState != .ended })
        {
            debug(.default, "Waiting for Live Activity to end...")
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s sleep
        }

        Task { @MainActor in
            await self.pushUpdate(contentState)
        }
        debug(.default, "Restarted Live Activity from LiveActivityIntent (via iOS Shortcut)")
    }
}

@available(iOS 16.2, *)
extension LiveActivityManager {
    /// Updates the live activity when new glucose data is available.
    ///
    /// This function adjusts the live activity content based on new glucose readings and triggers an update to the live activity.
    /// - Parameter glucose: An array of `GlucoseData` objects.
    @MainActor func glucoseDidUpdate(_ glucose: [GlucoseData]) {
        guard settings.useLiveActivity else {
            if currentActivity != nil {
                Task {
                    await self.endActivity()
                }
            }
            return
        }

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
                units: settings.units,
                chart: glucose,
                settings: settings,
                determination: determination,
                override: override,
                widgetItems: widgetItems
            )

            if let content = content {
                Task {
                    await self.pushUpdate(content)
                }
            }
        }
    }
}
