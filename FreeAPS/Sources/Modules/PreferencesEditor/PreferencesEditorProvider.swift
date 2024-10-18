import Foundation
import HealthKit

extension PreferencesEditor {
    final class Provider: BaseProvider, PreferencesEditorProvider {
        @Injected() private var settingsManager: SettingsManager!
        @Injected() var fetchGlucoseManager: FetchGlucoseManager!
        private let processQueue = DispatchQueue(label: "PreferencesEditorProvider.processQueue")

        var preferences: Preferences {
            settingsManager.preferences
        }

        func savePreferences(_ preferences: Preferences) {
            processQueue.async {
                var prefs = preferences
                prefs.timestamp = Date()
                self.storage.save(prefs, as: OpenAPS.Settings.preferences)
            }
        }

        func updateManagerUnits() {
            var manager = fetchGlucoseManager.cgmManager
            let managerName = manager.map { "\(type(of: $0))" } ?? "nil"
            let units = settingsManager.settings.units
            let loopkitUnits: HKUnit = units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter
            print("manager: \(managerName) is changing units to: \(loopkitUnits.description) ")
            manager?.unitDidChange(to: loopkitUnits)
        }

        func migrateUnits() {
            migrateTargets()
            migrateISF()
        }

        private func migrateTargets() {
            let profile = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mmolL, userPrefferedUnits: .mmolL, targets: [])

            let units = settingsManager.settings.units
            guard units != profile.units else { return }

            let targets = profile.targets.map { target -> BGTargetEntry in
                if units == .mmolL {
                    return BGTargetEntry(
                        low: Decimal(round(Double(target.low.asMmolL) * 10) / 10),
                        high: Decimal(round(Double(target.high.asMmolL) * 10) / 10),
                        start: target.start,
                        offset: target.offset
                    )
                } else {
                    return BGTargetEntry(
                        low: Decimal(round(Double(target.low.asMgdL))),
                        high: Decimal(round(Double(target.high.asMgdL))),
                        start: target.start,
                        offset: target.offset
                    )
                }
            }

            let newProfile = BGTargets(units: units, userPrefferedUnits: units, targets: targets)
            storage.save(newProfile, as: OpenAPS.Settings.bgTargets)
        }

        private func migrateISF() {
            let profile = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                ?? InsulinSensitivities(
                    units: .mmolL,
                    userPrefferedUnits: .mmolL,
                    sensitivities: []
                )
            let units = settingsManager.settings.units
            guard units != profile.units else { return }

            let sensitivities = profile.sensitivities.map { item -> InsulinSensitivityEntry in

                if units == .mmolL {
                    return InsulinSensitivityEntry(
                        sensitivity: Decimal(round(Double(item.sensitivity.asMmolL) * 10) / 10),
                        offset: item.offset,
                        start: item.start
                    )
                } else {
                    return InsulinSensitivityEntry(
                        sensitivity: Decimal(round(Double(item.sensitivity.asMgdL))),
                        offset: item.offset,
                        start: item.start
                    )
                }
            }

            let newProfile = InsulinSensitivities(units: units, userPrefferedUnits: units, sensitivities: sensitivities)

            storage.save(newProfile, as: OpenAPS.Settings.insulinSensitivities)
        }
    }
}
