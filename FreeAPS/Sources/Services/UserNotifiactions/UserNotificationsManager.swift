import AudioToolbox
import Foundation
import LoopKit
import SwiftUI
import Swinject
import UIKit
import UserNotifications

protocol UserNotificationsManager {}

enum GlucoseSourceKey: String {
    case transmitterBattery
    case nightscoutPing
    case description
}

enum NotificationAction: String {
    static let key = "action"

    case snooze
}

protocol BolusFailureObserver {
    func bolusDidFail()
}

protocol pumpNotificationObserver {
    func pumpNotification(alert: AlertEntry)
    func pumpRemoveNotification()
}

final class BaseUserNotificationsManager: NSObject, UserNotificationsManager, Injectable {
    private enum Identifier: String {
        case glucocoseNotification = "FreeAPS.glucoseNotification"
        case carbsRequiredNotification = "FreeAPS.carbsRequiredNotification"
        case noLoopFirstNotification = "FreeAPS.noLoopFirstNotification"
        case noLoopSecondNotification = "FreeAPS.noLoopSecondNotification"
        case bolusFailedNotification = "FreeAPS.bolusFailedNotification"
        case pumpNotification = "FreeAPS.pumpNotification"
    }

    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var router: Router!

    @Injected(as: FetchGlucoseManager.self) private var sourceInfoProvider: SourceInfoProvider!

    @Persisted(key: "UserNotificationsManager.snoozeUntilDate") private var snoozeUntilDate: Date = .distantPast

    private let center = UNUserNotificationCenter.current()
    private var lifetime = Lifetime()

    private let context = CoreDataStack.shared.persistentContainer.viewContext

    init(resolver: Resolver) {
        super.init()
        center.delegate = self
        injectServices(resolver)
        broadcaster.register(GlucoseObserver.self, observer: self)
        broadcaster.register(DeterminationObserver.self, observer: self)
        broadcaster.register(BolusFailureObserver.self, observer: self)
        broadcaster.register(pumpNotificationObserver.self, observer: self)

        requestNotificationPermissionsIfNeeded()
        sendGlucoseNotification()
        subscribeOnLoop()
    }

    private func subscribeOnLoop() {
        apsManager.lastLoopDateSubject
            .sink { [weak self] date in
                self?.scheduleMissingLoopNotifiactions(date: date)
            }
            .store(in: &lifetime)
    }

    private func addAppBadge(glucose: Int?) {
        guard let glucose = glucose, settingsManager.settings.glucoseBadge else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = 0
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
            UIApplication.shared.applicationIconBadgeNumber = badge
        }
    }

    private func notifyCarbsRequired(_ carbs: Int) {
        guard Decimal(carbs) >= settingsManager.settings.carbsRequiredThreshold else { return }

        ensureCanSendNotification {
            var titles: [String] = []

            let content = UNMutableNotificationContent()

            if self.snoozeUntilDate > Date() {
                titles.append(NSLocalizedString("(Snoozed)", comment: "(Snoozed)"))
            } else {
                content.sound = .default
                self.playSoundIfNeeded()
            }

            titles.append(String(format: NSLocalizedString("Carbs required: %d g", comment: "Carbs required"), carbs))

            content.title = titles.joined(separator: " ")
            content.body = String(
                format: NSLocalizedString(
                    "To prevent LOW required %d g of carbs",
                    comment: "To prevent LOW required %d g of carbs"
                ),
                carbs
            )

            self.addRequest(identifier: .carbsRequiredNotification, content: content, deleteOld: true)
        }
    }

    private func scheduleMissingLoopNotifiactions(date _: Date) {
        ensureCanSendNotification {
<<<<<<< HEAD
            let title = NSLocalizedString("iAPS not active", comment: "iAPS not active")
=======
            let title = NSLocalizedString("Trio Not Active", comment: "Trio Not Active")
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
            let body = NSLocalizedString("Last loop was more than %d min ago", comment: "Last loop was more than %d min ago")

            let firstInterval = 20 // min
            let secondInterval = 40 // min

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

            self.addRequest(
                identifier: .noLoopFirstNotification,
                content: firstContent,
                deleteOld: true,
                trigger: firstTrigger
            )
            self.addRequest(
                identifier: .noLoopSecondNotification,
                content: secondContent,
                deleteOld: true,
                trigger: secondTrigger
            )
        }
    }

    private func notifyBolusFailure() {
        ensureCanSendNotification {
            let title = NSLocalizedString("Bolus failed", comment: "Bolus failed")
            let body = NSLocalizedString(
                "Bolus failed or inaccurate. Check pump history before repeating.",
                comment: "Bolus failed or inaccurate. Check pump history before repeating."
            )

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            self.addRequest(
                identifier: .noLoopFirstNotification,
                content: content,
                deleteOld: true,
                trigger: nil
            )
        }
    }

    private func fetchGlucose() -> [GlucoseStored]? {
        CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateFor20MinAgo,
            key: "date",
            ascending: true,
            fetchLimit: 3
        )
    }

    private func sendGlucoseNotification() {
        addAppBadge(glucose: nil)

        context.perform {
            guard let glucose = self.fetchGlucose(), let lastValue = glucose.first, let lastReading = glucose.first?.glucose,
                  let lastDirection = lastValue.direction,
                  let secondLastReading = glucose.dropFirst().first?.glucose else { return }

            self.addAppBadge(glucose: (glucose.first?.glucose).map { Int($0) })

            guard self.glucoseStorage.alarm != nil || self.settingsManager.settings.glucoseNotificationsAlways else {
                return
            }

            self.ensureCanSendNotification {
                var titles: [String] = []
                var notificationAlarm = false

                switch self.glucoseStorage.alarm {
                case .none:
                    titles.append(NSLocalizedString("Glucose", comment: "Glucose"))
                case .low:
                    titles.append(NSLocalizedString("LOWALERT!", comment: "LOWALERT!"))
                    notificationAlarm = true
                case .high:
                    titles.append(NSLocalizedString("HIGHALERT!", comment: "HIGHALERT!"))
                    notificationAlarm = true
                }

                let delta = glucose.count >= 2 ? lastReading - secondLastReading : nil
                let body = self.glucoseText(
                    glucoseValue: Int(lastReading),
                    delta: Int(delta ?? 0),
                    direction: lastDirection
                ) + self
                    .infoBody()

                if self.snoozeUntilDate > Date() {
                    titles.append(NSLocalizedString("(Snoozed)", comment: "(Snoozed)"))
                    notificationAlarm = false
                } else {
                    titles.append(body)
                    let content = UNMutableNotificationContent()
                    content.title = titles.joined(separator: " ")
                    content.body = body

                    if notificationAlarm {
                        self.playSoundIfNeeded()
                        content.sound = .default
                        content.userInfo[NotificationAction.key] = NotificationAction.snooze.rawValue
                    }

                    self.addRequest(identifier: .glucocoseNotification, content: content, deleteOld: true)
                }
            }
        }
    }

<<<<<<< HEAD
    private func glucoseText(glucoseValue: Int, delta: Int?, direction: String?) -> String {
=======
    private func glucoseText(glucoseValue: Int, delta: Int?, direction: BloodGlucose.Direction?) -> String {
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
        let units = settingsManager.settings.units
        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? glucoseValue
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)! + " " + NSLocalizedString(units.rawValue, comment: "units")
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
                            format: NSLocalizedString("Nightscout ping: %d ms", comment: "Nightscout ping"),
                            Int(ping * 1000)
                        )
                )
            }

            // Transmitter battery
            if let transmitterBattery = info[GlucoseSourceKey.transmitterBattery.rawValue] as? Int {
                body.append(
                    "\n"
                        + String(
                            format: NSLocalizedString("Transmitter: %@%%", comment: "Transmitter: %@%%"),
                            "\(transmitterBattery)"
                        )
                )
            }
        }
        return body
    }

    private func requestNotificationPermissionsIfNeeded() {
        center.getNotificationSettings { settings in
            debug(.service, "UNUserNotificationCenter.authorizationStatus: \(String(describing: settings.authorizationStatus))")
            if ![.authorized, .provisional].contains(settings.authorizationStatus) {
                self.requestNotificationPermissions()
            }
        }
    }

    private func requestNotificationPermissions() {
        debug(.service, "requestNotificationPermissions")
        center.requestAuthorization(options: [.badge, .sound, .alert]) { granted, error in
            if granted {
                debug(.service, "requestNotificationPermissions was granted")
            } else {
                warning(.service, "requestNotificationPermissions failed", error: error)
            }
        }
    }

    private func ensureCanSendNotification(_ completion: @escaping () -> Void) {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                warning(.service, "ensureCanSendNotification failed, authorization denied")
                return
            }

            debug(.service, "Sending notification was allowed")

            completion()
        }
    }

    private func addRequest(
        identifier: Identifier,
        content: UNMutableNotificationContent,
        deleteOld: Bool = false,
        trigger: UNNotificationTrigger? = nil
    ) {
        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: trigger)

        if deleteOld {
            DispatchQueue.main.async {
                self.center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
                self.center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.center.add(request) { error in
                if let error = error {
                    warning(.service, "Unable to addNotificationRequest", error: error)
                    return
                }

                debug(.service, "Sending \(identifier) notification")
            }
        }
    }

    private func playSoundIfNeeded() {
        guard settingsManager.settings.useAlarmSound, snoozeUntilDate < Date() else { return }
        Self.stopPlaying = false
        playSound()
    }

    static let soundID: UInt32 = 1336
    private static var stopPlaying = false

    private func playSound(times: Int = 1) {
        guard times > 0, !Self.stopPlaying else {
            return
        }

        AudioServicesPlaySystemSoundWithCompletion(Self.soundID) {
            self.playSound(times: times - 1)
        }
    }

    static func stopSound() {
        stopPlaying = true
        AudioServicesDisposeSystemSoundID(soundID)
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

extension BaseUserNotificationsManager: GlucoseObserver {
    func glucoseDidUpdate(_: [BloodGlucose]) {
        sendGlucoseNotification()
    }
}

extension BaseUserNotificationsManager: pumpNotificationObserver {
    func pumpNotification(alert: AlertEntry) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = alert.contentTitle ?? "Unknown"
            content.body = alert.contentBody ?? "Unknown"
            content.sound = .default
            self.addRequest(
                identifier: .pumpNotification,
                content: content,
                deleteOld: true,
                trigger: nil
            )
        }
    }

    func pumpRemoveNotification() {
        let identifier: Identifier = .pumpNotification
        DispatchQueue.main.async {
            self.center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            self.center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
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
        completionHandler([.banner, .badge, .sound])
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
        }
    }
}
