import Foundation

extension DynamicISFExplorer {
    final class StateModel: BaseStateModel<Provider> {
        @Published var inputs = Inputs()
        @Published var includeOverride = false

        private(set) var savedInputs = Inputs()
        private(set) var activeOverride: ActiveOverride?
        private(set) var units: GlucoseUnits = .mgdL
        /// The custom peak times the loop accepts for the user's insulin curve.
        private(set) var insulinPeakTimeRange: ClosedRange<Decimal> = 35 ... 120

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

        /// Whether the active override changes either curve on the chart; only sigmoid uses the target.
        var overrideAffectsCurve: Bool {
            guard let activeOverride else { return false }
            let usesTarget = inputs.sigmoid || hasChanges && savedInputs.sigmoid
            return activeOverride.adjustsSensitivity || usesTarget && activeOverride.target != nil
        }

        /// While included, an override target takes the place of the sigmoid's profile target.
        var overrideReplacesTarget: Bool {
            inputs.sigmoid && appliedOverride?.target != nil
        }

        private var appliedOverride: ActiveOverride? {
            includeOverride && overrideAffectsCurve ? activeOverride : nil
        }

        override func subscribe() {
            units = settingsManager.settings.units

            let preferences = settingsManager.preferences
            let peakSetting = PickerSettingsProvider.shared.settings.insulinPeakTime
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
            insulinPeakTimeRange = customPeak(peakSetting.min, for: preferences.curve) ...
                customPeak(peakSetting.max, for: preferences.curve)
        }

        func reset() {
            inputs = savedInputs
        }

        /// The peak time Dynamic ISF uses: fixed per curve without a custom peak (see `DynamicISF.calculate`),
        /// otherwise the custom peak as the profile clamps it.
        private func insulinPeakTime(for preferences: Preferences) -> Decimal {
            guard preferences.useCustomPeakTime else { return preferences.curve == .ultraRapid ? 50 : 65 }
            return customPeak(preferences.insulinPeakTime, for: preferences.curve)
        }

        private func customPeak(_ peak: Decimal, for curve: InsulinCurve) -> Decimal {
            IobCalculation.lookupPeak(curve: curve, useCustomPeakTime: true, insulinPeakTime: peak).map { Decimal($0) } ?? peak
        }
    }
}
