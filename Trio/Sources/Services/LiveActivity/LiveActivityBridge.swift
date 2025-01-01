import ActivityKit
import Combine
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
        case .active:
            break
        @unknown default:
            return true
        }
        return -startDate.timeIntervalSinceNow > TimeInterval(60 * 60)
    }
}

@available(iOS 16.2, *)
final class LiveActivityBridge: Injectable, ObservableObject, SettingsObserver {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var storage: FileStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!

    private let activityAuthorizationInfo = ActivityAuthorizationInfo()
    @Published private(set) var systemEnabled: Bool

    private var settings: TrioSettings {
        settingsManager.settings
    }

    var determination: DeterminationData?
    private var currentActivity: ActiveActivity?
    private var latestGlucose: GlucoseData?
    var glucoseFromPersistence: [GlucoseData]?
    var override: OverrideData?
    var widgetItems: [LiveActivityAttributes.LiveActivityItem]?

    let context = CoreDataStack.shared.newTaskContext()

    private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    init(resolver: Resolver) {
        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: DispatchQueue.global(qos: .background))
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

    func settingsDidChange(_: TrioSettings) {
        Task {
            await updateContentState(determination)
        }
    }

    private func registerHandler() {
        coreDataPublisher?.filterByEntityName("OverrideStored").sink { [weak self] _ in
            guard let self = self else { return }
            self.overridesDidUpdate()
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("OrefDetermination").sink { [weak self] _ in
            guard let self = self else { return }
            self.cobOrIobDidUpdate()
        }.store(in: &subscriptions)
    }

    private func registerSubscribers() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.setupGlucoseArray()
            }
            .store(in: &subscriptions)
    }

    private func cobOrIobDidUpdate() {
        Task { @MainActor in
            self.determination = await fetchAndMapDetermination()
            if let determination = determination {
                await self.updateContentState(determination)
            }
        }
    }

    private func overridesDidUpdate() {
        Task { @MainActor in
            self.override = await fetchAndMapOverride()
            if let determination = determination {
                await self.updateContentState(determination)
            }
        }
    }

    @objc private func handleLiveActivityOrderChange() {
        Task {
            self.widgetItems = UserDefaults.standard.loadLiveActivityOrderFromUserDefaults() ?? LiveActivityAttributes
                .LiveActivityItem.defaultItems
            await self.updateLiveActivityOrder()
        }
    }

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

    @MainActor private func updateLiveActivityOrder() async {
        Task {
            await updateContentState(determination)
        }
    }

    private func setupGlucoseArray() {
        Task { @MainActor in
            self.glucoseFromPersistence = await fetchAndMapGlucose()
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

    @MainActor private func pushUpdate(_ state: LiveActivityAttributes.ContentState) async {
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
                    staleDate: min(state.date ?? Date.now, Date.now).addingTimeInterval(360) // 6 minutes in seconds
                )
                await currentActivity.activity.update(content)
            }
        } else {
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

                await pushUpdate(state)
            } catch {
                debug(
                    .default,
                    "\(#file): Error creating new activity: \(error)"
                )
            }
        }
    }

    private func endActivity() async {
        if let currentActivity {
            await currentActivity.activity.end(nil, dismissalPolicy: .immediate)
            self.currentActivity = nil
        }

        for unknownActivity in Activity<LiveActivityAttributes>.activities {
            await unknownActivity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

@available(iOS 16.2, *)
extension LiveActivityBridge {
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
