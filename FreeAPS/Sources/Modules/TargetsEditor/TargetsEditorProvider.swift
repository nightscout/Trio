extension TargetsEditor {
    final class Provider: BaseProvider, TargetsEditorProvider {
        var profile: BGTargets {
            storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mgdL, userPrefferedUnits: .mgdL, targets: [])
        }

        func saveProfile(_ profile: BGTargets) {
            storage.save(profile, as: OpenAPS.Settings.bgTargets)
        }
    }
}
