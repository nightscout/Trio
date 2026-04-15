import Observation
import SwiftUI

extension SMBSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        var units: GlucoseUnits = .mgdL

        @Published var enableSMBAlways: Bool = false
        @Published var maxDeltaBGthreshold: Decimal = 0.2
        @Published var enableSMBWithCOB: Bool = false
        @Published var enableSMBWithTemptarget: Bool = false
        @Published var enableSMBAfterCarbs: Bool = false
        @Published var allowSMBWithHighTemptarget: Bool = false
        @Published var enableSMB_high_bg: Bool = false
        @Published var enableSMB_high_bg_target: Decimal = 100
        @Published var maxSMBBasalMinutes: Decimal = 30
        @Published var bolusIncrement: Decimal = 0.1 // get this from pump, dafuq?: Bool = false
        @Published var enableUAM: Bool = false
        @Published var maxUAMSMBBasalMinutes: Decimal = 30

        override func subscribe() {
            units = settingsManager.settings.units

            subscribePreferencesSetting(\.enableSMBAlways, on: $enableSMBAlways) { enableSMBAlways = $0 }
            subscribePreferencesSetting(\.maxDeltaBGthreshold, on: $maxDeltaBGthreshold) { maxDeltaBGthreshold = $0 }
            subscribePreferencesSetting(\.enableSMBWithCOB, on: $enableSMBWithCOB) { enableSMBWithCOB = $0 }
            subscribePreferencesSetting(\.enableSMBWithTemptarget, on: $enableSMBWithTemptarget) { enableSMBWithTemptarget = $0 }
            subscribePreferencesSetting(\.enableSMBAfterCarbs, on: $enableSMBAfterCarbs) { enableSMBAfterCarbs = $0 }
            subscribePreferencesSetting(\.allowSMBWithHighTemptarget, on: $allowSMBWithHighTemptarget) {
                allowSMBWithHighTemptarget = $0 }
            subscribePreferencesSetting(\.enableSMB_high_bg, on: $enableSMB_high_bg) { enableSMB_high_bg = $0 }
            subscribePreferencesSetting(\.enableSMB_high_bg_target, on: $enableSMB_high_bg_target) {
                enableSMB_high_bg_target = $0 }
            subscribePreferencesSetting(\.maxSMBBasalMinutes, on: $maxSMBBasalMinutes) { maxSMBBasalMinutes = $0 }
            subscribePreferencesSetting(\.bolusIncrement, on: $bolusIncrement) { bolusIncrement = $0 }
            subscribePreferencesSetting(\.enableUAM, on: $enableUAM) { enableUAM = $0 }
            subscribePreferencesSetting(\.maxUAMSMBBasalMinutes, on: $maxUAMSMBBasalMinutes) { maxUAMSMBBasalMinutes = $0 }
        }
    }
}

extension SMBSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
