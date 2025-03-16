import SwiftUI

extension GlucoseNotificationSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Published var glucoseBadge = false
        @Published var glucoseNotificationsOption: GlucoseNotificationsOption = .onlyAlarmLimits
        @Published var addSourceInfoToGlucoseNotifications = false
        @Published var lowGlucose: Decimal = 0
        @Published var highGlucose: Decimal = 0

        @Published var notificationsPump = true
        @Published var notificationsCgm = true
        @Published var notificationsCarb = true
        @Published var notificationsAlgorithm = true

        var units: GlucoseUnits = .mgdL

        override func subscribe() {
            let units = settingsManager.settings.units
            self.units = units

            subscribeSetting(\.notificationsPump, on: $notificationsPump) { notificationsPump = $0 }
            subscribeSetting(\.notificationsCgm, on: $notificationsCgm) { notificationsCgm = $0 }
            subscribeSetting(\.notificationsCarb, on: $notificationsCarb) { notificationsCarb = $0 }
            subscribeSetting(\.notificationsAlgorithm, on: $notificationsAlgorithm) { notificationsAlgorithm = $0 }

            subscribeSetting(\.glucoseBadge, on: $glucoseBadge) { glucoseBadge = $0 }
            subscribeSetting(\.glucoseNotificationsOption, on: $glucoseNotificationsOption) { glucoseNotificationsOption = $0 }
            subscribeSetting(\.addSourceInfoToGlucoseNotifications, on: $addSourceInfoToGlucoseNotifications) {
                addSourceInfoToGlucoseNotifications = $0 }

            subscribeSetting(\.lowGlucose, on: $lowGlucose, initial: {
                lowGlucose = $0
            }, map: {
                let clampedValue = max(min($0, 400), 40)
                return clampedValue
            })

            subscribeSetting(\.highGlucose, on: $highGlucose, initial: {
                highGlucose = $0
            }, map: {
                let clampedValue = max(min($0, 400), 40)
                return clampedValue
            })
        }
    }
}

extension GlucoseNotificationSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
