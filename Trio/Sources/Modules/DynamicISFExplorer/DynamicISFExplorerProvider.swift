import Foundation

extension DynamicISFExplorer {
    final class Provider: BaseProvider, DynamicISFExplorerProvider {
        func sensitivity(at date: Date) -> Decimal? {
            guard let sensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities)),
                let sensitivity = try? Isf.isfLookup(isfDataInput: sensitivities, timestamp: date).0,
                sensitivity > 0 // the lookup returns -1 for a malformed schedule
            else { return nil }

            return sensitivity
        }

        func target(at date: Date) -> Decimal? {
            guard let targets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets)),
                let target = try? Targets.bgTargetsLookup(targets: targets, tempTargets: [], profile: Profile(), now: date).1
            else { return nil }

            return target.minBg?.rounded()
        }

        var orefVariables: TrioCustomOrefVariables? {
            storage.retrieve(OpenAPS.Monitor.trio_custom_oref_variables, as: TrioCustomOrefVariables.self)
        }
    }
}
