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

protocol pumpNotificationObserver {
    func pumpNotification(alert: AlertEntry)
    func pumpRemoveNotification()
}

final class BaseUserNotificationsManager: NSObject, UserNotificationsManager, Injectable {
    enum Identifier: String {
        case glucoseNotification = "Trio.glucoseNotification"
        case carbsRequiredNotification = "Trio.carbsRequiredNotification"
        case noLoopFirstNotification = "Trio.noLoopFirstNotification"
        case noLoopSecondNotification = "Trio.noLoopSecondNotification"
        case bolusFailedNotification = "Trio.bolusFailedNotification"
        case pumpNotification = "Trio.pumpNotification"
        case alertMessageNotification = "Trio.alertMessageNotification"
    }

    @Injected() var alertPermissionsChecker: AlertPermissionsChecker!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var router: Router!

    @Injected(as: FetchGlucoseManager.self) private var sourceInfoProvider: SourceInfoProvider!

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
        broadcaster.register(BolusFailureObserver.self, observer: self)
        broadcaster.register(pumpNotificationObserver.self, observer: self)
        broadcaster.register(alertMessageNotificationObserver.self, observer: self)
//        requestNotificationPermissionsIfNeeded()
        Task {
            await sendGlucoseNotification()
        }
        registerHandlers()
        registerSubscribers()
        subscribeOnLoop()
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
              settingsManager.settings.showCarbsRequiredBadge, settingsManager.settings.notificationsCarb else { return }

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

    private func notifyBolusFailure() {
        let title = String(localized: "Bolus failed", comment: "Bolus failed")
        let body = String(
            localized:
            "Bolus failed or inaccurate. Check pump history before repeating.",
            comment: "Bolus failed or inaccurate. Check pump history before repeating."
        )
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        addRequest(
            identifier: .noLoopFirstNotification,
            content: content,
            deleteOld: true,
            trigger: nil,
            messageType: .error,
            messageSubtype: .pump
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

    @MainActor private func sendGlucoseNotification() async {
        do {
            addAppBadge(glucose: nil)
            let glucoseIDs = try await fetchGlucoseIDs()
            let glucoseObjects = try glucoseIDs.compactMap { id in
                try viewContext.existingObject(with: id) as? GlucoseStored
            }

            guard let lastReading = glucoseObjects.first?.glucose,
                  let secondLastReading = glucoseObjects.dropFirst().first?.glucose,
                  let lastDirection = glucoseObjects.first?.directionEnum?.symbol else { return }

            addAppBadge(glucose: (glucoseObjects.first?.glucose).map { Int($0) })

            var titles: [String] = []
            var notificationAlarm = false
            var messageType = MessageType.info

            switch glucoseStorage.alarm {
            case .none:
                titles.append(String(localized: "Glucose", comment: "Glucose"))
            case .low:
                titles.append(String(localized: "LOWALERT!", comment: "LOWALERT!"))
                messageType = MessageType.warning
                notificationAlarm = true
            case .high:
                titles.append(String(localized: "HIGHALERT!", comment: "HIGHALERT!"))
                messageType = MessageType.warning
                notificationAlarm = true
            }

            let delta = glucoseObjects.count >= 2 ? lastReading - secondLastReading : nil
            let body = glucoseText(
                glucoseValue: Int(lastReading),
                delta: Int(delta ?? 0),
                direction: lastDirection
            ) + infoBody()

            if snoozeUntilDate > Date() {
                titles.append(String(localized: "(Snoozed)", comment: "(Snoozed)"))
                notificationAlarm = false
            } else {
                titles.append(body)
                let content = UNMutableNotificationContent()
                content.title = titles.joined(separator: " ")
                content.body = body

                if notificationAlarm {
                    content.sound = .default
                    content.userInfo[NotificationAction.key] = NotificationAction.snooze.rawValue
                }

                addRequest(
                    identifier: .glucoseNotification,
                    content: content,
                    deleteOld: true,
                    messageType: messageType,
                    messageSubtype: .glucose,
                    action: NotificationAction.snooze
                )
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to send glucose notification with error: \(error)"
            )
        }
    }

    private func glucoseText(glucoseValue: Int, delta: Int?, direction: String?) -> String {
        let units = settingsManager.settings.units
        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? glucoseValue
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)! + " " + String(localized: "\(units.rawValue)", comment: "units")
        let directionText = direction ?? "↔︎"
        let deltaText = delta
            .map {
                self.deltaFormatter
                    .string(from: Double(
                        units == .mmolL ? $0
                            .asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return glucoseText + " " + directionText + " " + deltaText
    }

    private func infoBody() -> String {
        var body = ""

        if settingsManager.settings.addSourceInfoToGlucoseNotifications,
           let info = sourceInfoProvider.sourceInfo()
        {
            // Description
            if let description = info[GlucoseSourceKey.description.rawValue] as? String {
                body.append("\n" + description)
            }

            // NS ping
            if let ping = info[GlucoseSourceKey.nightscoutPing.rawValue] as? TimeInterval {
                body.append(
                    "\n"
                        + String(
                            format: String(localized: "Nightscout ping: %d ms", comment: "Nightscout ping"),
                            Int(ping * 1000)
                        )
                )
            }

            // Transmitter battery
            if let transmitterBattery = info[GlucoseSourceKey.transmitterBattery.rawValue] as? Int {
                body.append(
                    "\n"
                        + String(
                            format: String(localized: "Transmitter: %@%%", comment: "Transmitter: %@%%"),
                            "\(transmitterBattery)"
                        )
                )
            }
        }
        return body
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
        alertIdentifier = identifier == .pumpNotification ? alertIdentifier + content
            .title : (identifier == .alertMessageNotification ? alertIdentifier + content.body : alertIdentifier)
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

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
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
        case .pump:
            if message.type == .info || message.type == .error {
                identifier = Identifier.alertMessageNotification
            } else {
                identifier = .pumpNotification
            }
        case .carb:
            identifier = .carbsRequiredNotification
        case .glucose:
            identifier = .glucoseNotification
        case .algorithm:
            if message.trigger != nil {
                identifier = message.content.contains(String(firstInterval)) ? Identifier.noLoopFirstNotification : Identifier
                    .noLoopSecondNotification
            } else {
                identifier = Identifier.alertMessageNotification
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

extension BaseUserNotificationsManager: pumpNotificationObserver {
    func pumpNotification(alert: AlertEntry) {
        let content = UNMutableNotificationContent()
        let alertUp = alert.alertIdentifier.uppercased()
        let typeMessage: MessageType
        if alertUp.contains("FAULT") || alertUp.contains("ERROR") {
            content.userInfo[NotificationAction.key] = NotificationAction.pumpConfig.rawValue
            typeMessage = .error
        } else {
            typeMessage = .warning
            guard settingsManager.settings.notificationsPump else { return }
        }
        content.title = alert.contentTitle ?? "Unknown"
        content.body = alert.contentBody ?? "Unknown"
        content.sound = .default
        addRequest(
            identifier: .pumpNotification,
            content: content,
            deleteOld: true,
            trigger: nil,
            messageType: typeMessage,
            messageSubtype: .pump,
            action: .pumpConfig
        )
    }

    func pumpRemoveNotification() {
        let identifier: Identifier = .pumpNotification
        DispatchQueue.main.async {
            self.notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }
    }
}

extension BaseUserNotificationsManager: DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination) {
        guard let carndRequired = determination.carbsReq else { return }
        notifyCarbsRequired(Int(carndRequired))
    }
}

extension BaseUserNotificationsManager: BolusFailureObserver {
    func bolusDidFail() {
        notifyBolusFailure()
    }
}

extension BaseUserNotificationsManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound, .list])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let actionRaw = response.notification.request.content.userInfo[NotificationAction.key] as? String,
              let action = NotificationAction(rawValue: actionRaw)
        else { return }

        switch action {
        case .snooze:
            router.mainModalScreen.send(.snooze)
        case .pumpConfig:
            let messageCont = MessageContent(
                content: response.notification.request.content.body,
                type: MessageType.other,
                subtype: .pump,
                useAPN: false,
                action: .pumpConfig
            )
            router.alertMessage.send(messageCont)
        default: break
        }
    }
}
