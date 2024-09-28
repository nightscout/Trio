import Observation
import SwiftUI

extension SMBSettings {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var settings: SettingsManager!
        @ObservationIgnored @Injected() var storage: FileStorage!

        var units: GlucoseUnits = .mgdL

        var enableSMBAlways: Bool = false
        var maxDeltaBGthreshold: Decimal = 0.2
        var enableSMBWithCOB: Bool = false
        var enableSMBWithTemptarget: Bool = false
        var enableSMBAfterCarbs: Bool = false
        var allowSMBWithHighTemptarget: Bool = false
        var enableSMB_high_bg: Bool = false
        var enableSMB_high_bg_target: Decimal = 100
        var maxSMBBasalMinutes: Decimal = 30
        var smbDeliveryRatio: Decimal = 0.5
        var smbInterval: Decimal = 3
        var bolusIncrement: Decimal = 0.1 // get this from pump, dafuq?: Bool = false
        var enableUAM: Bool = false
        var maxUAMSMBBasalMinutes: Decimal = 30

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
