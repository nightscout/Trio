import SwiftUI

extension SMBSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL

        @Published var enableSMBAlways: Bool = false
        @Published var maxDeltaBGthreshold: Decimal = 0.2
        @Published var enableSMBWithCOB: Bool = false
        @Published var enableSMBWithTemptarget: Bool = false
        @Published var enableSMBAfterCarbs: Bool = false
        @Published var allowSMBWithHighTemptarget: Bool = false
        @Published var enableSMB_high_bg: Bool = false
        @Published var enableSMB_high_bg_target: Decimal = 100
        @Published var maxSMBBasalMinutes: Decimal = 30
        @Published var smbDeliveryRatio: Decimal = 0.5
        @Published var smbInterval: Decimal = 3
        @Published var bolusIncrement: Decimal = 0.1 // get this from pump, dafuq?: Bool = false
        @Published var enableUAM: Bool = false
        @Published var maxUAMSMBBasalMinutes: Decimal = 30

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            units = settingsManager.settings.units
            enableSMBAlways = settings.preferences.enableSMBAlways
            maxDeltaBGthreshold = settings.preferences.maxDeltaBGthreshold
            enableSMBWithCOB = settings.preferences.enableSMBWithCOB
            enableSMBWithTemptarget = settings.preferences.enableSMBWithTemptarget
            enableSMBAfterCarbs = settings.preferences.enableSMBAfterCarbs
            allowSMBWithHighTemptarget = settings.preferences.allowSMBWithHighTemptarget
            enableSMB_high_bg = settings.preferences.enableSMB_high_bg
            enableSMB_high_bg_target = settings
                .preferences.enableSMB_high_bg_target
            maxSMBBasalMinutes = settings.preferences.maxSMBBasalMinutes
            smbDeliveryRatio = settings.preferences.smbDeliveryRatio
            smbInterval = settings.preferences.smbInterval
            bolusIncrement = settings.preferences.bolusIncrement
            enableUAM = settings.preferences.enableUAM
            maxUAMSMBBasalMinutes = settings.preferences.maxUAMSMBBasalMinutes
        }

        var isSettingUnchanged: Bool {
            preferences.enableSMBAlways == enableSMBAlways &&
                preferences.maxDeltaBGthreshold == maxDeltaBGthreshold &&
                preferences.enableSMBWithCOB == enableSMBWithCOB &&
                preferences.enableSMBWithTemptarget == enableSMBWithTemptarget &&
                preferences.enableSMBAfterCarbs == enableSMBAfterCarbs &&
                preferences.allowSMBWithHighTemptarget == allowSMBWithHighTemptarget &&
                preferences.enableSMB_high_bg == enableSMB_high_bg &&
                preferences.enableSMB_high_bg_target == enableSMB_high_bg_target &&
                preferences.maxSMBBasalMinutes == maxSMBBasalMinutes &&
                preferences.smbDeliveryRatio == smbDeliveryRatio &&
                preferences.smbInterval == smbInterval &&
                preferences.bolusIncrement == bolusIncrement &&
                preferences.enableUAM == enableUAM &&
                preferences.maxUAMSMBBasalMinutes == maxUAMSMBBasalMinutes
        }

        func saveIfChanged() {
            if !isSettingUnchanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
                newSettings.enableSMBAlways = enableSMBAlways
                newSettings.maxDeltaBGthreshold = maxDeltaBGthreshold
                newSettings.enableSMBWithCOB = enableSMBWithCOB
                newSettings.enableSMBWithTemptarget = enableSMBWithTemptarget
                newSettings.enableSMBAfterCarbs = enableSMBAfterCarbs
                newSettings.allowSMBWithHighTemptarget = allowSMBWithHighTemptarget
                newSettings.enableSMB_high_bg = enableSMB_high_bg
                newSettings.enableSMB_high_bg_target = enableSMB_high_bg_target
                newSettings.maxSMBBasalMinutes = maxSMBBasalMinutes
                newSettings.smbDeliveryRatio = smbDeliveryRatio
                newSettings.smbInterval = smbInterval
                newSettings.bolusIncrement = bolusIncrement
                newSettings.enableUAM = enableUAM
                newSettings.maxUAMSMBBasalMinutes = maxUAMSMBBasalMinutes
                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }
    }
}

extension SMBSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
