import Foundation

extension TargetsEditor {
    final class Provider: BaseProvider, TargetsEditorProvider {
        var profile: BGTargets {
            var retrievedTargets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])

            // migrate existing mmol/L Trio users from mmol/L settings to pure mg/dl settings
            if retrievedTargets.units == .mmolL || retrievedTargets.userPreferredUnits == .mmolL {
                let convertedTargets = retrievedTargets.targets.map { target in
                    BGTargetEntry(
                        low: storage.parseSettingIfMmolL(value: target.low),
                        high: storage.parseSettingIfMmolL(value: target.high),
                        start: target.start,
                        offset: target.offset
                    )
                }
                retrievedTargets = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: convertedTargets)
                saveProfile(retrievedTargets)
            }

            return retrievedTargets
        }

        func saveProfile(_ profile: BGTargets) {
            storage.save(profile, as: OpenAPS.Settings.bgTargets)
        }
    }
}
