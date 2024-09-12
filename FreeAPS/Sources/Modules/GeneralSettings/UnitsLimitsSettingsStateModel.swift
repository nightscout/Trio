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

            maxBasal = pumpSettings.maxBasal
            maxBolus = pumpSettings.maxBolus
            maxIOB = settings.preferences.maxIOB
            maxCOB = settings.preferences.maxCOB
        }

        var isPumpSettingUnchanged: Bool {
            pumpSettings.maxBasal == maxBasal &&
                pumpSettings.maxBolus == maxBolus
        }

        var isSettingUnchanged: Bool {
            preferences.maxIOB == maxIOB &&
                preferences.maxCOB == maxCOB
        }

        func saveIfChanged() {
            if !isSettingUnchanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()

                newSettings.maxIOB = maxIOB
                newSettings.maxCOB = maxCOB

                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }

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
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
