extension OverrideConfig {
    final class Provider: BaseProvider, OverrideProvider {
        func getBGTarget() async -> BGTargets {
            await storage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        }
    }
}
