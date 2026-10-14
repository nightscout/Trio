import Foundation

extension DynamicISFExplorer {
    final class StateModel: BaseStateModel<Provider> {
        @Published var inputs = Inputs()
        @Published var includeOverride = false

        private(set) var savedInputs = Inputs()
        private(set) var activeOverride: ActiveOverride?
        private(set) var units: GlucoseUnits = .mgdL

        var hasChanges: Bool {
            inputs != savedInputs
        }

        var curve: Curve? {
            Curve(inputs: inputs, override: appliedOverride)
        }

        /// The curve for the user's actual settings, shown for comparison once something has been changed.
        var savedCurve: Curve? {
            hasChanges ? Curve(inputs: savedInputs, override: appliedOverride) : nil
        }

        private var appliedOverride: ActiveOverride? {
            includeOverride ? activeOverride : nil
        }

        override func subscribe() {
            units = settingsManager.settings.units

            let preferences = settingsManager.preferences
            let orefVariables = provider.orefVariables
            let defaults = Inputs()
            let now = Date()

            savedInputs = Inputs(
                sigmoid: preferences.sigmoid,
                adjustmentFactor: preferences.adjustmentFactor,
                adjustmentFactorSigmoid: preferences.adjustmentFactorSigmoid,
                autosensMin: preferences.autosensMin,
                autosensMax: preferences.autosensMax,
                insulinPeakTime: insulinPeakTime(for: preferences),
                sensitivity: provider.sensitivity(at: now) ?? defaults.sensitivity,
                target: provider.target(at: now) ?? defaults.target,
                tddLast24Hours: orefVariables?.past2hoursAverage ?? 0,
                tddTenDayAverage: orefVariables?.average_total_data ?? 0,
                weightPercentage: preferences.weightPercentage
            )
            inputs = savedInputs
            activeOverride = orefVariables.flatMap { ActiveOverride($0) }
        }

        func reset() {
            inputs = savedInputs
        }

        /// The peak time Dynamic ISF uses, which without a custom peak is fixed per curve (see `DynamicISF.calculate`).
        private func insulinPeakTime(for preferences: Preferences) -> Decimal {
            guard !preferences.useCustomPeakTime else { return preferences.insulinPeakTime }
            return preferences.curve == .ultraRapid ? 50 : 65
        }
    }
}
