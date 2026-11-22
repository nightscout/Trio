import Combine
import SwiftUI

extension UnitsLimitsSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!
        @Injected() private var tidepoolManager: TidepoolManager!
        @Injected() private var therapyProfileManager: TherapyProfileManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var unitsIndex = 0 // index 0 is mg/dl

        @Published var maxBolus: Decimal = 10
        @Published var maxBasal: Decimal = 2
        @Published var maxIOB: Decimal = 0
        @Published var maxCOB: Decimal = 120
        @Published var hasChanged: Bool = false
        @Published var threshold_setting: Decimal = 60
        /// Names the profiles a lower max basal rate keeps from being activated.
        @Published var maxBasalProfileWarning: String?

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

            let currentProblems = therapyProfileManager.activationProblems()
            $maxBasal
                .removeDuplicates()
                .map { [weak self] in self?.profileWarning(maxBasal: $0, currentProblems: currentProblems) }
                .assign(to: &$maxBasalProfileWarning)
        }

        /// Names the profiles that the edited max basal rate keeps from being activated, when the stored one does not.
        private func profileWarning(maxBasal: Decimal, currentProblems: [String: String]) -> String? {
            guard maxBasal != pumpSettings.maxBasal else { return nil }
            let names = therapyProfileManager.activationProblems(maxBasal: maxBasal).keys
                .filter { currentProblems[$0] == nil }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            guard !names.isEmpty else { return nil }
            return String(
                localized: "These profiles have basal rates above \(maxBasal.formatted()) U/hr and cannot be activated until they are edited: \(names.joined(separator: ", "))."
            )
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

                        Task.detached(priority: .low) {
                            await self.tidepoolManager.uploadSettings()
                        }
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
