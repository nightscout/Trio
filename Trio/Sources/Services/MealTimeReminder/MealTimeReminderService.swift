import Foundation
import LoopKit
import Swinject

#if canImport(AlarmKit)
    import AlarmKit
#endif

struct PendingMealTimeReminder: Equatable, Codable {
    var fireDate: Date
    var carbs: Decimal
    var bolusAmount: Decimal
    /// The AlarmKit alarm backing this reminder (iOS 26+ path only), persisted so a cancel
    /// after an app restart can still reach it.
    var alarmID: UUID?
}

protocol MealTimeReminderService: AnyObject {
    func requestAuthorization() async

    /// Schedules the reminder immediately. Used for external insulin, where there is no pump
    /// delivery to wait for.
    @discardableResult func scheduleEatReminder(after leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) async -> Bool

    /// Registers the reminder to be scheduled once the pump reports the bolus has finished
    /// delivering (or was cancelled early), so the lead time is not eaten into by the delivery.
    func prepareEatReminder(after leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) async

    @MainActor func cancelPendingReminders()

    @MainActor var pendingReminder: PendingMealTimeReminder? { get }
}

@Observable final class BaseMealTimeReminderService: MealTimeReminderService, Injectable {
    @ObservationIgnored @Injected() private var broadcaster: Broadcaster!
    @ObservationIgnored @Injected() private var trioAlertManager: TrioAlertManager!

    private static let pendingReminderDefaultsKey = "Trio.mealTimeReminderPending"

    /// LoopKit alert identifier for the pre-iOS 26 path.
    private static let alertIdentifier = Alert.Identifier.mealTimeReminderEat

    /// Extra time past the lead time after which an awaiting bolus completion is considered
    /// lost (pump went silent mid-delivery), so a much-later, unrelated completion can't
    /// schedule a stale reminder.
    private static let staleCompletionAllowance: TimeInterval = 5 * 60

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

    /// The AlarmKit alarm this service scheduled, so cancel never touches foreign alarms (e.g.
    /// the critical safety alarms that share `AlarmManager.shared`).
    @MainActor private var scheduledAlarmID: UUID?

    init(resolver: Resolver) {
        injectServices(resolver)
        broadcaster.register(BolusDeliveryObserver.self, observer: self)
        Task { await restorePendingReminder() }
    }

    func requestAuthorization() async {
        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                let manager = AlarmManager.shared
                if manager.authorizationState == .notDetermined {
                    _ = try? await manager.requestAuthorization()
                }
            }
        #endif
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
                if let alarmID = await scheduleAlarm(leadTime: leadTime, carbs: carbs, bolusAmount: bolusAmount) {
                    await setPendingReminder(PendingMealTimeReminder(
                        fireDate: Date().addingTimeInterval(leadTime),
                        carbs: carbs,
                        bolusAmount: bolusAmount,
                        alarmID: alarmID
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
            bolusAmount: bolusAmount,
            alarmID: nil
        ))
        return true
    }

    func prepareEatReminder(
        after leadTime: TimeInterval,
        carbs: Decimal,
        bolusAmount _: Decimal
    ) async {
        guard leadTime > 0 else { return }

        await cancelPendingReminders()

        let awaiting = AwaitingBolusCompletion(id: UUID(), leadTime: leadTime, carbs: carbs)
        await MainActor.run { awaitingCompletion = awaiting }
        debug(.bolus, "Meal-time reminder awaiting bolus completion: \(Int(leadTime / 60)) min lead time")

        await MainActor.run {
            startAwaitingExpiry(awaiting, after: leadTime + Self.staleCompletionAllowance)
        }
    }

    /// Once delivery plus lead time would surely have passed, drop the awaiting record so a
    /// much-later, unrelated completion can't schedule a stale reminder.
    @MainActor private func startAwaitingExpiry(_ awaiting: AwaitingBolusCompletion, after delay: TimeInterval) {
        awaitingExpiryTask?.cancel()
        awaitingExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.awaitingCompletion == awaiting else { return }
                debug(.bolus, "Meal-time reminder dropped: bolus completion never arrived")
                self.awaitingCompletion = nil
            }
        }
    }

    @MainActor func cancelPendingReminders() {
        awaitingCompletion = nil
        awaitingExpiryTask?.cancel()
        awaitingExpiryTask = nil

        // Must run before setPendingReminder(nil), which clears scheduledAlarmID.
        #if canImport(AlarmKit)
            if #available(iOS 26.0, *), let alarmID = scheduledAlarmID {
                // cancel clears a scheduled or counting-down alarm; an already alerting one
                // rejects cancel and needs stop instead.
                do {
                    try AlarmManager.shared.cancel(id: alarmID)
                    debug(.bolus, "Meal-time reminder alarm canceled: \(alarmID)")
                } catch {
                    do {
                        try AlarmManager.shared.stop(id: alarmID)
                        debug(.bolus, "Meal-time reminder alarm stopped: \(alarmID)")
                    } catch {
                        warning(.bolus, "Meal-time reminder alarm cancel/stop failed: \(error.localizedDescription)")
                    }
                }
                scheduledAlarmID = nil
            }
        #endif

        setPendingReminder(nil)

        trioAlertManager.retractAlert(identifier: Self.alertIdentifier)
    }

    // MARK: - Pending-reminder state (in-app banner)

    @MainActor private func setPendingReminder(_ reminder: PendingMealTimeReminder?) {
        expiryTask?.cancel()
        expiryTask = nil
        pendingReminder = reminder
        scheduledAlarmID = reminder?.alarmID

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
        debug(
            .bolus,
            "Meal-time reminder restored: fires at \(reminder.fireDate), alarmID \(reminder.alarmID?.uuidString ?? "none")"
        )

        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                let alarms = (try? AlarmManager.shared.alarms) ?? []
                debug(
                    .bolus,
                    "Meal-time reminder sees \(alarms.count) system alarm(s): \(alarms.map { "\($0.id) state=\($0.state)" })"
                )
            }
        #endif
    }

    // MARK: - AlarmKit (iOS 26+)

    #if canImport(AlarmKit)
        @available(iOS 26.0, *) private func scheduleAlarm(
            leadTime: TimeInterval,
            carbs: Decimal,
            bolusAmount: Decimal
        ) async -> UUID? {
            let manager = AlarmManager.shared

            var authorization = manager.authorizationState
            if authorization == .notDetermined {
                authorization = (try? await manager.requestAuthorization()) ?? .denied
            }
            guard authorization == .authorized else {
                debug(.bolus, "Meal-time reminder alarm not scheduled: AlarmKit authorization is \(authorization)")
                return nil
            }

            let presentation = AlarmPresentation(
                alert: makeAlert(),
                countdown: AlarmPresentation.Countdown(title: "Time to eat in")
            )

            let attributes = AlarmAttributes<MealTimeReminderMetadata>(
                presentation: presentation,
                metadata: MealTimeReminderMetadata(
                    carbs: NSDecimalNumber(decimal: carbs).doubleValue,
                    bolusAmount: NSDecimalNumber(decimal: bolusAmount).doubleValue
                ),
                tintColor: MealTimeReminderStyle.tint
            )

            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: leadTime,
                attributes: attributes,
                sound: .default
            )

            do {
                let alarmID = UUID()
                _ = try await manager.schedule(id: alarmID, configuration: configuration)
                debug(.bolus, "Meal-time reminder alarm scheduled for \(Int(leadTime / 60)) min")
                return alarmID
            } catch {
                warning(.bolus, "Failed to schedule meal-time reminder alarm: \(error)")
                return nil
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

    // MARK: - LoopKit alert (pre-iOS 26)

    /// Routes the reminder through Trio's alert pipeline: an in-app banner while the app is
    /// open, a time-sensitive notification otherwise. Cancellation goes through
    /// `retractAlert`, which also resets the throttler so an immediate re-issue isn't dropped.
    private func issueEatAlert(leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) {
        let content = Alert.Content(
            title: String(localized: "Meal-Time Reminder"),
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

    private static func reminderBody(carbs: Decimal, bolusAmount: Decimal) -> String {
        let carbsText = Formatter.integerFormatter.string(from: carbs as NSDecimalNumber) ?? "\(carbs)"
        let bolusText = Formatter.decimalFormatterWithTwoFractionDigits
            .string(from: bolusAmount as NSDecimalNumber) ?? "\(bolusAmount)"

        switch (bolusAmount > 0, carbs > 0) {
        case (true, true):
            return String(
                localized: "Time to eat! You bolused \(bolusText) U for \(carbsText) g of carbs."
            )
        case (true, false):
            return String(localized: "Time to eat! You bolused \(bolusText) U.")
        case (false, true):
            return String(localized: "Time to eat! You logged \(carbsText) g of carbs.")
        case (false, false):
            return String(localized: "Time to eat!")
        }
    }
}

extension BaseMealTimeReminderService: BolusDeliveryObserver {
    /// The lead time starts when delivery actually stops, not when the pump accepted the command.
    /// A cancelled bolus still schedules the reminder for whatever was delivered; zero delivered
    /// means there is nothing to cover.
    func bolusDeliveryDidFinish(deliveredUnits: Double) {
        Task { @MainActor in
            guard let awaiting = awaitingCompletion else { return }
            debug(.bolus, "Bolus delivery finished with \(deliveredUnits) U; scheduling meal-time reminder")
            awaitingCompletion = nil
            awaitingExpiryTask?.cancel()
            awaitingExpiryTask = nil

            guard deliveredUnits > 0 else {
                cancelPendingReminders()
                return
            }

            await scheduleEatReminder(
                after: awaiting.leadTime,
                carbs: awaiting.carbs,
                bolusAmount: Decimal(deliveredUnits)
            )
        }
    }
}

extension Alert.Identifier {
    /// Fallback alert for the pre-iOS 26 meal-time reminder. The user arms the reminder
    /// explicitly, so the alert pipeline lets it pierce the global snooze the same way
    /// critical alerts do (see `BaseTrioAlertManager.issueAlert`).
    static let mealTimeReminderEat = Alert.Identifier(
        managerIdentifier: "Trio.mealTimeReminder",
        alertIdentifier: "eatReminder"
    )
}
