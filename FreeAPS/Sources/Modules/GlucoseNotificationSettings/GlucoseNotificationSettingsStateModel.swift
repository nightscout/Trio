import SwiftUI

extension GlucoseNotificationSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Published var glucoseBadge = false
        @Published var glucoseNotificationsAlways = false
        @Published var useAlarmSound = false
        @Published var addSourceInfoToGlucoseNotifications = false
        @Published var lowGlucose: Decimal = 0
        @Published var highGlucose: Decimal = 0

        var units: GlucoseUnits = .mgdL

        override func subscribe() {
            let units = settingsManager.settings.units
            self.units = units

            subscribeSetting(\.glucoseBadge, on: $glucoseBadge) { glucoseBadge = $0 }
            subscribeSetting(\.glucoseNotificationsAlways, on: $glucoseNotificationsAlways) { glucoseNotificationsAlways = $0 }
            subscribeSetting(\.useAlarmSound, on: $useAlarmSound) { useAlarmSound = $0 }
            subscribeSetting(\.addSourceInfoToGlucoseNotifications, on: $addSourceInfoToGlucoseNotifications) {
                addSourceInfoToGlucoseNotifications = $0 }
            subscribeSetting(\.lowGlucose, on: $lowGlucose, initial: {
                let value = max(min($0, 400), 40)
                lowGlucose = value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.highGlucose, on: $highGlucose, initial: {
                let value = max(min($0, 400), 40)
                highGlucose = value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })
        }
    }
}

extension GlucoseNotificationSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
