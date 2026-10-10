import Foundation
import Swinject
import UserNotifications

#if canImport(AlarmKit)
    import AlarmKit
#endif

struct PendingPreBolusReminder: Equatable, Codable {
    var fireDate: Date
    var carbs: Decimal
    var bolusAmount: Decimal
}

protocol PreBolusAlarmService: AnyObject {
    func requestAuthorization() async

    @discardableResult func scheduleEatReminder(after leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) async -> Bool

    @MainActor func cancelPendingReminders()

    @MainActor var pendingReminder: PendingPreBolusReminder? { get }
}

@Observable final class BasePreBolusAlarmService: PreBolusAlarmService, Injectable {
    @ObservationIgnored private let notificationCenter = UNUserNotificationCenter.current()

    /// Fixed identifier so a second pre-bolus replaces the first rather than stacking.
    private static let notificationIdentifier = "Trio.preBolusTimer"
    private static let pendingReminderDefaultsKey = "Trio.preBolusPendingReminder"

    @MainActor private(set) var pendingReminder: PendingPreBolusReminder?

    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init(resolver: Resolver) {
        injectServices(resolver)
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
                    await setPendingReminder(PendingPreBolusReminder(
                        fireDate: Date().addingTimeInterval(leadTime),
                        carbs: carbs,
                        bolusAmount: bolusAmount
                    ))
                    return true
                }
                // Fall through to a notification so the user still gets told when to eat.
            }
        #endif

        let scheduled = await scheduleNotification(leadTime: leadTime, carbs: carbs, bolusAmount: bolusAmount)
        if scheduled {
            await setPendingReminder(PendingPreBolusReminder(
                fireDate: Date().addingTimeInterval(leadTime),
                carbs: carbs,
                bolusAmount: bolusAmount
            ))
        }
        return scheduled
    }

    @MainActor func cancelPendingReminders() {
        setPendingReminder(nil)

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])

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

    @MainActor private func setPendingReminder(_ reminder: PendingPreBolusReminder?) {
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
              let reminder = try? JSONDecoder().decode(PendingPreBolusReminder.self, from: data)
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
                debug(.bolusState, "Pre-bolus alarm not scheduled: AlarmKit authorization is \(authorization)")
                return false
            }

            let presentation = AlarmPresentation(
                alert: makeAlert(),
                countdown: AlarmPresentation.Countdown(title: "Pre-bolus: time to eat in")
            )

            let attributes = AlarmAttributes<PreBolusAlarmMetadata>(
                presentation: presentation,
                metadata: PreBolusAlarmMetadata(
                    carbs: NSDecimalNumber(decimal: carbs).doubleValue,
                    bolusAmount: NSDecimalNumber(decimal: bolusAmount).doubleValue,
                    bolusDate: Date()
                ),
                tintColor: PreBolusAlarmStyle.tint
            )

            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: leadTime,
                attributes: attributes,
                sound: .default
            )

            do {
                _ = try await manager.schedule(id: UUID(), configuration: configuration)
                debug(.bolusState, "Pre-bolus alarm scheduled for \(Int(leadTime / 60)) min")
                return true
            } catch {
                warning(.bolusState, "Failed to schedule pre-bolus alarm: \(error)")
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

    // MARK: - Local notification fallback (iOS 17–25)

    private func scheduleNotification(leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) async -> Bool {
        let status = await notificationCenter.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            debug(.bolusState, "Pre-bolus reminder not scheduled: notification authorization is \(status.rawValue)")
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
            warning(.bolusState, "Failed to schedule pre-bolus reminder: \(error)")
            return false
        }
    }

    private static func reminderBody(carbs: Decimal, bolusAmount: Decimal) -> String {
        let carbsText = Formatter.integerFormatter.string(from: carbs as NSDecimalNumber) ?? "\(carbs)"
        let bolusText = Formatter.decimalFormatterWithTwoFractionDigits
            .string(from: bolusAmount as NSDecimalNumber) ?? "\(bolusAmount)"

        return String(
            localized: "Pre-bolus complete. Time to eat! You bolused \(bolusText) U for \(carbsText) g of carbs."
        )
    }
}
