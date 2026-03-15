import Combine
import SwiftUI

extension UnitsLimitsSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!

        @Published var units: GlucoseUnits = .mgdL
        @Published var unitsIndex = 0 // index 0 is mg/dl

        @Published var maxBolus: Decimal = 10
        @Published var maxBasal: Decimal = 2
        @Published var maxIOB: Decimal = 0
        @Published var maxCOB: Decimal = 120
        @Published var hasChanged: Bool = false
        @Published var threshold_setting: Decimal = 60

        var preferences: Preferences {
            settingsManager.preferences
        }

        var pumpSettings: PumpSettings {
            provider.settings()
        }

        override func subscribe() {
            units = settingsManager.settings.units
            subscribeSetting(\.units, on: $unitsIndex.map { $0 == 0 ? GlucoseUnits.mgdL : .mmolL }) {
                unitsIndex = $0 == .mgdL ? 0 : 1
            }

            subscribePreferencesSetting(\.maxIOB, on: $maxIOB) { maxIOB = $0 }
            subscribePreferencesSetting(\.maxCOB, on: $maxCOB) { maxCOB = $0 }
            subscribePreferencesSetting(\.threshold_setting, on: $threshold_setting) { threshold_setting = $0 }

            maxBasal = pumpSettings.maxBasal
            maxBolus = pumpSettings.maxBolus
        }

        var isPumpSettingUnchanged: Bool {
            pumpSettings.maxBasal == maxBasal &&
                pumpSettings.maxBolus == maxBolus
        }

        func saveIfChanged() {
            if !isPumpSettingUnchanged {
                let settings = PumpSettings(
                    insulinActionCurve: pumpSettings.insulinActionCurve,
                    maxBolus: maxBolus,
                    maxBasal: maxBasal
                )
                provider.save(settings: settings)
                    .receive(on: DispatchQueue.main)
                    .sink { _ in
                        let settings = self.provider.settings()
                        self.maxBasal = settings.maxBasal
                        self.maxBolus = settings.maxBolus
                    } receiveValue: {}
                    .store(in: &lifetime)
            }
        }
    }
}

extension UnitsLimitsSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
