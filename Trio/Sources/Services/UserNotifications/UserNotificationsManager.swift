import Combine
import CoreData
import Foundation
import LoopKit
import SwiftUI
import Swinject
import UserNotifications

protocol UserNotificationsManager {
    func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void)
    func requestNotificationPermissions(completion: @escaping (Bool) -> Void)
    @MainActor func applySnooze(for duration: TimeInterval) async
}

// MARK: - SnoozeObserver Protocol

protocol SnoozeObserver {
    @MainActor func snoozeDidChange(_ untilDate: Date)
}

final class BaseUserNotificationsManager: NSObject, UserNotificationsManager, Injectable {
    enum Identifier: String {
        case carbsRequiredNotification = "Trio.carbsRequiredNotification"
    }

    @Injected() var alertPermissionsChecker: AlertPermissionsChecker!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var trioAlertManager: TrioAlertManager!

    @Persisted(key: "UserNotificationsManager.snoozeUntilDate") private var snoozeUntilDate: Date = .distantPast

    private let notificationCenter = UNUserNotificationCenter.current()

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    // Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseUserNotificationsManager.queue", qos: .userInitiated)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    init(resolver: Resolver) {
        super.init()
        notificationCenter.delegate = self
        injectServices(resolver)

        coreDataPublisher =
            CoreDataStack.shared.entityChangePublisher
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        Task { await updateGlucoseBadge() }
        configureNotificationCategories()
        clearLegacyCarbsRequiredNotification()
        clearLegacyLoopNotifications()
        subscribeGlucoseUpdates()
    }

    private func configureNotificationCategories() {
        notificationCenter.getNotificationCategories { [weak self] existingCategories in
            guard let self else { return }

            let glucoseCategory = NotificationCategoryFactory.createGlucoseCategory()

            var categories = existingCategories
            categories.update(with: glucoseCategory)
            // UNUserNotificationCenter methods should be called on main thread
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.notificationCenter.setNotificationCategories(categories)
            }
        }
    }

    /// Subscribes to the two sources that signal a glucose change so the app
    /// icon badge stays current:
    /// - `coreDataPublisher` filtered to `GlucoseStored` — catches deletions
    ///   (batch inserts don't fire normal Core Data save notifications, so
    ///   inserts come through `updatePublisher` below).
    /// - `glucoseStorage.updatePublisher` — fires on every new reading.
    private func subscribeGlucoseUpdates() {
        coreDataPublisher?.filteredByEntityName("GlucoseStored")
            .sink { [weak self] _ in Task { await self?.updateGlucoseBadge() } }
            .store(in: &subscriptions)
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in Task { await self?.updateGlucoseBadge() } }
            .store(in: &subscriptions)
    }

    private func addAppBadge(glucose: Int?) {
        guard let glucose = glucose, settingsManager.settings.glucoseBadge else {
            DispatchQueue.main.async {
                self.notificationCenter.setBadgeCount(0) { error in
                    guard let error else {
                        return
                    }
                    print(error)
                }
            }
            return
        }

        let badge: Int
        if settingsManager.settings.units == .mmolL {
            badge = Int(round(Double((glucose * 10).asMmolL)))
        } else {
            badge = glucose
        }

        DispatchQueue.main.async {
            self.notificationCenter.setBadgeCount(badge) { error in
                guard let error else {
                    return
                }
                print(error)
            }
        }
    }

    /// Removes any `Trio.carbsRequiredNotification` UN still sitting in the
    /// system from a pre-pipeline install. Safe no-op when none exist.
    private func clearLegacyCarbsRequiredNotification() {
        let id = Identifier.carbsRequiredNotification.rawValue
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [id])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Purges the two "Last loop was X min ago" UNs the legacy
    /// `scheduleMissingLoopNotifiactions` path scheduled. Their identifiers
    /// aren't known to `NotLoopingMonitor`, so without this cleanup they'd
    /// fire once each after upgrade — https://github.com/nightscout/Trio/issues/1296
    private func clearLegacyLoopNotifications() {
        let ids = ["Trio.noLoopFirstNotification", "Trio.noLoopSecondNotification"]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func fetchGlucoseIDs() async throws -> [NSManagedObjectID] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchGlucoseIDs"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateFor20MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 3
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    /// Refreshes the Trio app icon badge from the latest stored glucose
    /// reading. Glucose alarm emission has moved to `GlucoseAlertCoordinator`
    /// (urgent-low / low / forecasted-low / high are issued via
    /// `TrioAlertManager` based on the user-configured `[GlucoseAlert]` list).
    @MainActor private func updateGlucoseBadge() async {
        do {
            addAppBadge(glucose: nil)
            let glucoseIDs = try await fetchGlucoseIDs()
            let latest = try glucoseIDs.compactMap { id in
                try viewContext.existingObject(with: id) as? GlucoseStored
            }.first?.glucose
            addAppBadge(glucose: latest.map { Int($0) })
        } catch {
            debug(.service, "Failed to update glucose badge: \(error)")
        }
    }

    func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void) {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                completionHandler(settings)
            }
        }
    }

    func requestNotificationPermissions(completion: @escaping (Bool) -> Void) {
        debug(.service, "requestNotificationPermissions")
        notificationCenter.requestAuthorization(options: [.badge, .sound, .alert]) { granted, error in
            if granted {
                debug(.service, "requestNotificationPermissions was granted")
                DispatchQueue.main.async {
                    completion(granted)
                }
            } else {
                warning(.service, "requestNotificationPermissions failed", error: error)
            }
        }
    }

    /// Forwards to the canonical snooze entry point on `TrioAlertManager`.
    /// All snooze surfaces (this method via UN actions / Watch / Snooze
    /// module / in-app banner) converge there so persistent state, mute
    /// window, and observers stay in sync.
    @MainActor func applySnooze(for duration: TimeInterval) async {
        await trioAlertManager.applySnooze(for: duration)
    }
}

extension BaseUserNotificationsManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if userInfo[AlertUserInfoKey.managerIdentifier.rawValue] is String {
            completionHandler([.badge, .list])
            return
        }
        completionHandler([.banner, .badge, .sound, .list])
    }

    /// UNUserNotificationCenterDelegate method called when user interacts with a notification.
    /// This can be called off the main thread, so we ensure all work happens on @MainActor.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        if userInfo[AlertUserInfoKey.managerIdentifier.rawValue] is String {
            trioAlertManager.handleNotificationResponse(response)
            return
        }

        // Handle quick snooze actions (from notification action buttons).
        if let quickAction = NotificationResponseAction(rawValue: response.actionIdentifier) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.applySnooze(for: quickAction.duration)
            }
        }
    }
}
