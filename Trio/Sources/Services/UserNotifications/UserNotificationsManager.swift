import AudioToolbox
import Combine
import CoreData
import Foundation
import LoopKit
import SwiftUI
import Swinject
import UIKit
import UserNotifications

protocol UserNotificationsManager {
    func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void)
    func requestNotificationPermissions(completion: @escaping (Bool) -> Void)
    @MainActor func applySnooze(for duration: TimeInterval) async
}

enum GlucoseSourceKey: String {
    case transmitterBattery
    case nightscoutPing
    case description
}

enum NotificationAction: String {
    static let key = "action"

    case snooze
    case pumpConfig
    case none
}

protocol BolusFailureObserver {
    func bolusDidFail()
}

protocol alertMessageNotificationObserver {
    func alertMessageNotification(_ message: MessageContent)
}

// MARK: - SnoozeObserver Protocol

protocol SnoozeObserver {
    @MainActor func snoozeDidChange(_ untilDate: Date)
}

final class BaseUserNotificationsManager: NSObject, UserNotificationsManager, Injectable {
    enum Identifier: String {
        case glucoseNotification = "Trio.glucoseNotification"
        case carbsRequiredNotification = "Trio.carbsRequiredNotification"
        case noLoopFirstNotification = "Trio.noLoopFirstNotification"
        case noLoopSecondNotification = "Trio.noLoopSecondNotification"
        case alertMessageNotification = "Trio.alertMessageNotification"
    }

    @Injected() var alertPermissionsChecker: AlertPermissionsChecker!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var router: Router!
    @Injected() private var trioAlertManager: TrioAlertManager!

    @Persisted(key: "UserNotificationsManager.snoozeUntilDate") private var snoozeUntilDate: Date = .distantPast

    private let notificationCenter = UNUserNotificationCenter.current()
    private var lifetime = Lifetime()

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    // Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseUserNotificationsManager.queue", qos: .userInitiated)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    let firstInterval = 20 // min
    let secondInterval = 40 // min

    init(resolver: Resolver) {
        super.init()
        notificationCenter.delegate = self
        injectServices(resolver)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        broadcaster.register(DeterminationObserver.self, observer: self)
        broadcaster.register(alertMessageNotificationObserver.self, observer: self)
//        requestNotificationPermissionsIfNeeded()
        Task {
            await sendGlucoseNotification()
        }
        configureNotificationCategories()
        registerHandlers()
        registerSubscribers()
        subscribeOnLoop()
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

    private func subscribeOnLoop() {
        apsManager.lastLoopDateSubject
            .sink { [weak self] date in
                self?.scheduleMissingLoopNotifiactions(date: date)
            }
            .store(in: &lifetime)
    }

    private func registerHandlers() {
        // Due to the Batch insert this only is used for observing Deletion of Glucose entries
        coreDataPublisher?.filteredByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.sendGlucoseNotification()
            }
        }.store(in: &subscriptions)
    }

    private func registerSubscribers() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.sendGlucoseNotification()
                }
            }
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

    private func notifyCarbsRequired(_ carbs: Int) {
        guard Decimal(carbs) >= settingsManager.settings.carbsRequiredThreshold,
              settingsManager.settings.showCarbsRequiredBadge else { return }

        var titles: [String] = []

        let content = UNMutableNotificationContent()

        if snoozeUntilDate > Date() {
            return
        }
        content.sound = .default

        titles.append(String(format: String(localized: "Carbs required: %d g", comment: "Carbs required"), carbs))

        content.title = titles.joined(separator: " ")
        content.body = String(
            format: String(
                localized:
                "To prevent LOW required %d g of carbs",
                comment: "To prevent LOW required %d g of carbs"
            ),
            carbs
        )
        addRequest(identifier: .carbsRequiredNotification, content: content, deleteOld: true, messageSubtype: .carb)
    }

    private func scheduleMissingLoopNotifiactions(date _: Date) {
        let title = String(localized: "Trio Not Active", comment: "Trio Not Active")
        let body = String(localized: "Last loop was more than %d min ago", comment: "Last loop was more than %d min ago")

        let firstContent = UNMutableNotificationContent()
        firstContent.title = title
        firstContent.body = String(format: body, firstInterval)
        firstContent.sound = .default

        let secondContent = UNMutableNotificationContent()
        secondContent.title = title
        secondContent.body = String(format: body, secondInterval)
        secondContent.sound = .default

        let firstTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * TimeInterval(firstInterval), repeats: false)
        let secondTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * TimeInterval(secondInterval), repeats: false)

        addRequest(
            identifier: .noLoopFirstNotification,
            content: firstContent,
            deleteOld: true,
            trigger: firstTrigger,
            messageType: .error,
            messageSubtype: .algorithm
        )
        addRequest(
            identifier: .noLoopSecondNotification,
            content: secondContent,
            deleteOld: true,
            trigger: secondTrigger,
            messageType: .error,
            messageSubtype: .algorithm
        )
    }

    private func fetchGlucoseIDs() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.predicateFor20MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 3
        )

        return try await backgroundContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    /// Maintains the app icon badge from the latest stored glucose reading.
    /// Glucose alarm emission has moved to `GlucoseAlertCoordinator` —
    /// urgent-low / low / forecasted-low / high are issued via `TrioAlertManager`
    /// based on the user-configured `[GlucoseAlert]` list.
    @MainActor private func sendGlucoseNotification() async {
        do {
            addAppBadge(glucose: nil)
            let glucoseIDs = try await fetchGlucoseIDs()
            let glucoseObjects = try glucoseIDs.compactMap { id in
                try viewContext.existingObject(with: id) as? GlucoseStored
            }
            addAppBadge(glucose: (glucoseObjects.first?.glucose).map { Int($0) })
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update glucose badge with error: \(error)"
            )
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

    @MainActor func applySnooze(for duration: TimeInterval) async {
        let untilDate = duration > 0 ? Date().addingTimeInterval(duration) : .distantPast
        snoozeUntilDate = untilDate
        // removeGlucoseNotifications() is safe to call here since we're @MainActor
        removeGlucoseNotifications()

        // Mirror the snooze into the unified AlertMuter so non-critical
        // LoopKit alerts (pump/cgm/algorithm) are suppressed during the
        // same window. Critical alerts (e.g. glucose.urgentLow) pierce
        // the mute in `TrioAlertManager.issueAlert`.
        if duration > 0 {
            trioAlertManager.muter.mute(for: duration)
        } else {
            trioAlertManager.muter.unmute()
        }

        // Notify observers that snooze was applied
        broadcaster.notify(SnoozeObserver.self, on: .main) { (observer: SnoozeObserver) in
            observer.snoozeDidChange(untilDate)
        }
    }

    private func addRequest(
        identifier: Identifier,
        content: UNMutableNotificationContent,
        deleteOld: Bool = false,
        trigger: UNNotificationTrigger? = nil,
        messageType: MessageType = MessageType.other,
        messageSubtype: MessageSubtype = MessageSubtype.misc,
        action: NotificationAction = NotificationAction.none
    ) {
        let messageCont = MessageContent(
            content: content.body,
            type: messageType,
            subtype: messageSubtype,
            title: content.title,
            useAPN: false,
            trigger: trigger,
            action: action
        )
        var alertIdentifier = identifier.rawValue
        if identifier == .alertMessageNotification {
            alertIdentifier += content.body
        }
        if deleteOld {
            DispatchQueue.main.async {
                self.notificationCenter.removeDeliveredNotifications(withIdentifiers: [alertIdentifier])
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [alertIdentifier])
            }
        }
        if alertPermissionsChecker.notificationsDisabled {
            router.alertMessage.send(messageCont)
            return
        }
        guard router.allowNotify(messageCont, settingsManager.settings) else { return }

        let request = UNNotificationRequest(identifier: alertIdentifier, content: content, trigger: trigger)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.notificationCenter.add(request) { error in
                if let error = error {
                    warning(.service, "Unable to addNotificationRequest", error: error)
                    return
                }

                debug(.service, "Sending \(identifier) notification for \(request.content.title)")
            }
        }
    }
}

extension BaseUserNotificationsManager: alertMessageNotificationObserver {
    func alertMessageNotification(_ message: MessageContent) {
        let content = UNMutableNotificationContent()
        var identifier: Identifier = .alertMessageNotification

        if message.title == "" {
            switch message.type {
            case .info:
                content.title = String(localized: "Info", comment: "Info title")
            case .warning:
                content.title = String(localized: "Warning", comment: "Warning title")
            case .error:
                content.title = String(localized: "Error", comment: "Error title")
            default:
                content.title = message.title
            }
        } else {
            content.title = message.title
        }
        switch message.subtype {
        case .carb:
            identifier = .carbsRequiredNotification
        case .glucose:
            identifier = .glucoseNotification
        case .algorithm:
            if message.trigger != nil {
                identifier = message.content.contains(String(firstInterval)) ? Identifier.noLoopFirstNotification : Identifier
                    .noLoopSecondNotification
            }
        default:
            identifier = .alertMessageNotification
        }
        switch message.action {
        case .snooze:
            content.userInfo[NotificationAction.key] = NotificationAction.snooze.rawValue
        case .pumpConfig:
            content.userInfo[NotificationAction.key] = NotificationAction.pumpConfig.rawValue
        default: break
        }

        content.body = String(localized: "\(message.content)", comment: "Info message")
        content.sound = .default
        addRequest(
            identifier: identifier,
            content: content,
            deleteOld: true,
            trigger: message.trigger,
            messageType: message.type,
            messageSubtype: message.subtype,
            action: message.action
        )
    }
}

extension BaseUserNotificationsManager {
    /// Removes all glucose notifications (delivered and pending).
    /// Must be called from the main thread. Safe to call from @MainActor contexts.
    @MainActor private func removeGlucoseNotifications() {
        let identifier = Identifier.glucoseNotification.rawValue
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

extension BaseUserNotificationsManager: DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination) {
        guard let carndRequired = determination.carbsReq else { return }
        notifyCarbsRequired(Int(carndRequired))
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

        // Handle quick snooze actions (from notification action buttons)
        if let quickAction = NotificationResponseAction(rawValue: response.actionIdentifier) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.applySnooze(for: quickAction.duration)
            }
            return
        }

        // Handle other notification actions (e.g., tapping notification body)
        guard let actionRaw = response.notification.request.content.userInfo[NotificationAction.key] as? String,
              let action = NotificationAction(rawValue: actionRaw)
        else { return }

        // Ensure UI operations happen on main thread using Task for consistency
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            switch action {
            case .snooze:
                self.router.mainModalScreen.send(.snooze)
            case .pumpConfig:
                let messageCont = MessageContent(
                    content: response.notification.request.content.body,
                    type: MessageType.other,
                    subtype: .pump,
                    useAPN: false,
                    action: .pumpConfig
                )
                self.router.alertMessage.send(messageCont)
            default: break
            }
        }
    }
}
