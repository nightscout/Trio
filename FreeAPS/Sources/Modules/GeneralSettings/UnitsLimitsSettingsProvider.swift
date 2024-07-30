import Foundation

extension UnitsLimitsSettings {
    final class Provider: BaseProvider, UnitsLimitsSettingsProvider {
        @Injected() private var settingsManager: SettingsManager!

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
