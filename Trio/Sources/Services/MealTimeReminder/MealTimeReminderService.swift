import Foundation
import LoopKit
import Swinject
import UserNotifications

#if canImport(AlarmKit)
    import AlarmKit
#endif

struct PendingMealTimeReminder: Equatable, Codable {
    var fireDate: Date
    var carbs: Decimal
    var bolusAmount: Decimal
}

protocol MealTimeReminderService: AnyObject {
    func requestAuthorization() async

    /// Schedules the reminder immediately. Used for external insulin, where there is no pump
    /// delivery to wait for.
    @discardableResult func scheduleEatReminder(after leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) async -> Bool

    /// Registers the reminder to be scheduled once the pump reports the bolus has finished
    /// delivering (or was cancelled early), so the lead time is not eaten into by the delivery.
    @discardableResult func prepareEatReminder(after leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) async -> Bool

    @MainActor func cancelPendingReminders()

    @MainActor var pendingReminder: PendingMealTimeReminder? { get }
}

@Observable final class BaseMealTimeReminderService: MealTimeReminderService, Injectable {
    @ObservationIgnored private let notificationCenter = UNUserNotificationCenter.current()
    @ObservationIgnored @Injected() private var broadcaster: Broadcaster!
    @ObservationIgnored @Injected() private var trioAlertManager: TrioAlertManager!

    /// Fixed identifier so a second meal-time reminder replaces the first rather than stacking.
    private static let notificationIdentifier = "Trio.mealTimeReminder"
    private static let pendingReminderDefaultsKey = "Trio.mealTimeReminderPending"

    /// LoopKit alert identifier for the iOS 17–25 path. Distinct from the backstop
    /// notification's identifier so retracting one can't clobber the other.
    private static let alertIdentifier = Alert.Identifier(
        managerIdentifier: "Trio.mealTimeReminder",
        alertIdentifier: "eatReminder"
    )

    /// Extra time past the lead time the backstop notification waits, roughly covering the bolus
    /// delivery in case the completion signal never arrives (e.g. the app was force-quit).
    private static let backstopDeliveryAllowance: TimeInterval = 5 * 60

    /// A reminder whose bolus is still delivering; scheduled once delivery stops.
    private struct AwaitingBolusCompletion: Equatable {
        let id: UUID
        let leadTime: TimeInterval
        let carbs: Decimal
    }

    @MainActor private(set) var pendingReminder: PendingMealTimeReminder?

    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    @ObservationIgnored private var awaitingCompletion: AwaitingBolusCompletion?
    @ObservationIgnored private var awaitingExpiryTask: Task<Void, Never>?

    init(resolver: Resolver) {
        injectServices(resolver)
        broadcaster.register(BolusDeliveryObserver.self, observer: self)
        Task { await restorePendingReminder() }
    }

    func requestAuthorization() async {
        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                let manager = AlarmManager.shared
                guard manager.authorizationState == .notDetermined else { return }
                _ = try? await manager.requestAuthorization()
            }
        #endif
        // The notification fallback uses the permission the app already requests at onboarding.
    }

    @discardableResult func scheduleEatReminder(
        after leadTime: TimeInterval,
        carbs: Decimal,
        bolusAmount: Decimal
    ) async -> Bool {
        guard leadTime > 0 else { return false }

        await cancelPendingReminders()

        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                if await scheduleAlarm(leadTime: leadTime, carbs: carbs, bolusAmount: bolusAmount) {
                    await setPendingReminder(PendingMealTimeReminder(
                        fireDate: Date().addingTimeInterval(leadTime),
                        carbs: carbs,
                        bolusAmount: bolusAmount
                    ))
                    return true
                }
                // Fall through to a LoopKit alert so the user still gets told when to eat.
            }
        #endif

        issueEatAlert(leadTime: leadTime, carbs: carbs, bolusAmount: bolusAmount)
        await setPendingReminder(PendingMealTimeReminder(
            fireDate: Date().addingTimeInterval(leadTime),
            carbs: carbs,
            bolusAmount: bolusAmount
        ))
        return true
    }

    @discardableResult func prepareEatReminder(
        after leadTime: TimeInterval,
        carbs: Decimal,
        bolusAmount: Decimal
    ) async -> Bool {
        guard leadTime > 0 else { return false }

        await cancelPendingReminders()

        let awaiting = AwaitingBolusCompletion(id: UUID(), leadTime: leadTime, carbs: carbs)
        await MainActor.run { awaitingCompletion = awaiting }

        // Backstop: if the bolus-completion signal never arrives, the user still gets reminded —
        // at worst `backstopDeliveryAllowance` later than the old schedule-at-enact behavior.
        let scheduled = await scheduleNotification(
            leadTime: leadTime + Self.backstopDeliveryAllowance,
            carbs: carbs,
            bolusAmount: bolusAmount
        )

        // Once the backstop would have fired, drop the awaiting record so a much-later,
        // unrelated completion can't schedule a stale reminder.
        let expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((leadTime + Self.backstopDeliveryAllowance) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.awaitingCompletion == awaiting else { return }
                self.awaitingCompletion = nil
            }
        }
        await MainActor.run { awaitingExpiryTask = expiryTask }

        return scheduled
    }

    @MainActor func cancelPendingReminders() {
        awaitingCompletion = nil
        awaitingExpiryTask?.cancel()
        awaitingExpiryTask = nil

        setPendingReminder(nil)

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        trioAlertManager.retractAlert(identifier: Self.alertIdentifier)

        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                // Trio schedules no other alarms, so clearing all of them is safe here.
                let manager = AlarmManager.shared
                for alarm in (try? manager.alarms) ?? [] {
                    try? manager.cancel(id: alarm.id)
                }
            }
        #endif
    }

    // MARK: - Pending-reminder state (in-app banner)

    @MainActor private func setPendingReminder(_ reminder: PendingMealTimeReminder?) {
        expiryTask?.cancel()
        expiryTask = nil
        pendingReminder = reminder

        guard let reminder else {
            UserDefaults.standard.removeObject(forKey: Self.pendingReminderDefaultsKey)
            return
        }

        UserDefaults.standard.set(try? JSONEncoder().encode(reminder), forKey: Self.pendingReminderDefaultsKey)

        expiryTask = Task { [weak self] in
            let delay = reminder.fireDate.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.pendingReminder == reminder else { return }
                self.setPendingReminder(nil)
            }
        }
    }

    /// Reloads the persisted reminder after a cold start, dropping it if it already fired.
    @MainActor private func restorePendingReminder() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingReminderDefaultsKey),
              let reminder = try? JSONDecoder().decode(PendingMealTimeReminder.self, from: data)
        else { return }

        guard reminder.fireDate > Date() else {
            UserDefaults.standard.removeObject(forKey: Self.pendingReminderDefaultsKey)
            return
        }

        setPendingReminder(reminder)
    }

    // MARK: - AlarmKit (iOS 26+)

    #if canImport(AlarmKit)
        @available(iOS 26.0, *) private func scheduleAlarm(
            leadTime: TimeInterval,
            carbs: Decimal,
            bolusAmount: Decimal
        ) async -> Bool {
            let manager = AlarmManager.shared

            var authorization = manager.authorizationState
            if authorization == .notDetermined {
                authorization = (try? await manager.requestAuthorization()) ?? .denied
            }
            guard authorization == .authorized else {
                debug(.bolusState, "Meal-time reminder alarm not scheduled: AlarmKit authorization is \(authorization)")
                return false
            }

            let presentation = AlarmPresentation(
                alert: makeAlert(),
                countdown: AlarmPresentation.Countdown(title: "Time to eat in")
            )

            let attributes = AlarmAttributes<MealTimeReminderMetadata>(
                presentation: presentation,
                metadata: MealTimeReminderMetadata(
                    carbs: NSDecimalNumber(decimal: carbs).doubleValue,
                    bolusAmount: NSDecimalNumber(decimal: bolusAmount).doubleValue,
                    bolusDate: Date()
                ),
                tintColor: MealTimeReminderStyle.tint
            )

            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: leadTime,
                attributes: attributes,
                sound: .default
            )

            do {
                _ = try await manager.schedule(id: UUID(), configuration: configuration)
                debug(.bolusState, "Meal-time reminder alarm scheduled for \(Int(leadTime / 60)) min")
                return true
            } catch {
                warning(.bolusState, "Failed to schedule meal-time reminder alarm: \(error)")
                return false
            }
        }

        /// `AlarmPresentation.Alert`'s initializer without a stop button is iOS 26.1+; on 26.0 we have to
        /// supply one even though the system no longer renders it.
        @available(iOS 26.0, *) private func makeAlert() -> AlarmPresentation.Alert {
            let title: LocalizedStringResource = "Time to eat"

            if #available(iOS 26.1, *) {
                return AlarmPresentation.Alert(title: title)
            } else {
                return AlarmPresentation.Alert(
                    title: title,
                    stopButton: AlarmButton(
                        text: "Eating now",
                        textColor: .white,
                        systemImageName: "fork.knife"
                    )
                )
            }
        }
    #endif

    // MARK: - LoopKit alert (iOS 17–25)

    /// Routes the reminder through Trio's alert pipeline: an in-app banner while the app is
    /// open, a time-sensitive notification otherwise. Cancellation goes through
    /// `retractAlert`, which also resets the throttler so an immediate re-issue isn't dropped.
    private func issueEatAlert(leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) {
        let content = Alert.Content(
            title: String(localized: "Time to eat"),
            body: Self.reminderBody(carbs: carbs, bolusAmount: bolusAmount),
            acknowledgeActionButtonLabel: String(localized: "OK")
        )
        let alert = Alert(
            identifier: Self.alertIdentifier,
            foregroundContent: content,
            backgroundContent: content,
            trigger: .delayed(interval: max(leadTime, 1)),
            interruptionLevel: .timeSensitive,
            sound: .sound(name: "chime.caf")
        )
        trioAlertManager.issueAlert(alert)
    }

    // MARK: - Backstop notification (app-killed case)

    private func scheduleNotification(leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) async -> Bool {
        let status = await notificationCenter.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            debug(.bolusState, "Meal-time reminder not scheduled: notification authorization is \(status.rawValue)")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to eat")
        content.body = Self.reminderBody(carbs: carbs, bolusAmount: bolusAmount)
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(leadTime, 1), repeats: false)
        )

        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            warning(.bolusState, "Failed to schedule meal-time reminder: \(error)")
            return false
        }
    }

    private static func reminderBody(carbs: Decimal, bolusAmount: Decimal) -> String {
        let carbsText = Formatter.integerFormatter.string(from: carbs as NSDecimalNumber) ?? "\(carbs)"
        let bolusText = Formatter.decimalFormatterWithTwoFractionDigits
            .string(from: bolusAmount as NSDecimalNumber) ?? "\(bolusAmount)"

        return String(
            localized: "Time to eat! You bolused \(bolusText) U for \(carbsText) g of carbs."
        )
    }
}

extension BaseMealTimeReminderService: BolusDeliveryObserver {
    /// The lead time starts when delivery actually stops, not when the pump accepted the command.
    /// A cancelled bolus still schedules the reminder for whatever was delivered; zero delivered
    /// means there is nothing to cover.
    func bolusDeliveryDidFinish(deliveredUnits: Double) {
        Task { @MainActor in
            guard let awaiting = awaitingCompletion else { return }
            awaitingCompletion = nil
            awaitingExpiryTask?.cancel()
            awaitingExpiryTask = nil

            guard deliveredUnits > 0 else {
                cancelPendingReminders()
                return
            }

            // scheduleEatReminder cancels the backstop notification (same identifier) before
            // setting the precise alarm.
            await scheduleEatReminder(
                after: awaiting.leadTime,
                carbs: awaiting.carbs,
                bolusAmount: Decimal(deliveredUnits)
            )
        }
    }
}
