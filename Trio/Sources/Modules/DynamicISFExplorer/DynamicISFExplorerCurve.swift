import Foundation

extension DynamicISFExplorer {
    /// The values that shape the Dynamic ISF curve. The explorer edits a copy of these and never saves them.
    /// Glucose values are in mg/dL, as the algorithm expects.
    struct Inputs: Equatable {
        var sigmoid = false
        var adjustmentFactor: Decimal = 0.8
        var adjustmentFactorSigmoid: Decimal = 0.5
        var autosensMin: Decimal = 0.7
        var autosensMax: Decimal = 1.2
        var insulinPeakTime: Decimal = 65
        var sensitivity: Decimal = 50
        var target: Decimal = 100
        var tddLast24Hours: Decimal = 0
        var tddTenDayAverage: Decimal = 0
        var weightPercentage: Decimal = 0.35

        var weightedTDD: Decimal {
            weightPercentage * tddLast24Hours + (1 - weightPercentage) * tddTenDayAverage
        }
    }

    /// The parts of an active override that change the Dynamic ISF curve.
    struct ActiveOverride: Equatable {
        let percentage: Decimal
        let adjustsSensitivity: Bool
        /// Override target in mg/dL, or `nil` when the override keeps the profile target.
        let target: Decimal?
    }

    /// Dynamic ISF across a range of glucose values, calculated with the same code the loop runs.
    struct Curve {
        struct Point: Identifiable {
            let glucose: Decimal
            let ratio: Decimal
            let sensitivity: Decimal

            var id: Decimal { glucose }
        }

        static let glucoseRange: ClosedRange<Decimal> = 40 ... 400

        /// Profile ISF after any override, before the dynamic ratio is applied.
        let profileSensitivity: Decimal
        /// The ISF range Autosens Max and Min allow, strongest to weakest.
        let sensitivityLimits: ClosedRange<Decimal>
        let points: [Point]

        /// Returns `nil` when Dynamic ISF would be off for these inputs, e.g. without any TDD
        /// or when Autosens Max and Min leave no room to adjust.
        init?(inputs: Inputs, override: ActiveOverride?) {
            var profile = Profile()
            profile.sens = inputs.sensitivity
            profile.minBg = inputs.target
            profile.autosensMin = inputs.autosensMin
            profile.autosensMax = inputs.autosensMax
            profile.insulinPeakTime = inputs.insulinPeakTime
            profile.weightPercentage = inputs.weightPercentage

            var preferences = Preferences()
            preferences.useNewFormula = true
            preferences.sigmoid = inputs.sigmoid
            preferences.adjustmentFactor = inputs.adjustmentFactor
            preferences.adjustmentFactorSigmoid = inputs.adjustmentFactorSigmoid
            preferences.useCustomPeakTime = true

            let variables = TrioCustomOrefVariables(inputs: inputs, override: override)

            var points: [Point] = []
            for glucose in stride(from: Self.glucoseRange.lowerBound, through: Self.glucoseRange.upperBound, by: 5) {
                guard let result = DynamicISF.calculate(
                    profile: profile,
                    preferences: preferences,
                    currentGlucose: glucose,
                    trioCustomOrefVariables: variables
                ) else { return nil }

                let sensitivity = DeterminationGenerator.computeAdjustedSensitivity(
                    sensitivity: inputs.sensitivity,
                    sensitivityRatio: result.ratio,
                    trioCustomOrefVariables: variables
                )
                points.append(Point(glucose: glucose, ratio: result.ratio, sensitivity: sensitivity))
            }

            let profileSensitivity = variables.override(sensitivity: inputs.sensitivity)
            self.profileSensitivity = profileSensitivity
            sensitivityLimits = profileSensitivity / inputs.autosensMax ... profileSensitivity / inputs.autosensMin
            self.points = points
        }

        func point(nearest glucose: Decimal) -> Point? {
            points.min { abs($0.glucose - glucose) < abs($1.glucose - glucose) }
        }
    }
}

extension DynamicISFExplorer.ActiveOverride {
    init?(_ variables: TrioCustomOrefVariables) {
        // 0 and 6 both mean "no override target", see `Profile.profileTarget(trioCustomOrefVariables:)`
        let target = [0, 6].contains(variables.overrideTarget) ? nil : variables.overrideTarget
        let adjustsSensitivity = variables.isf || variables.isfAndCr

        guard variables.useOverride, adjustsSensitivity || target != nil else { return nil }

        self.init(percentage: variables.overridePercentage, adjustsSensitivity: adjustsSensitivity, target: target)
    }
}

private extension TrioCustomOrefVariables {
    /// Only the TDD and override values Dynamic ISF reads; everything else is left neutral.
    init(inputs: DynamicISFExplorer.Inputs, override: DynamicISFExplorer.ActiveOverride?) {
        self.init(
            average_total_data: inputs.tddTenDayAverage,
            weightedAverage: inputs.weightedTDD,
            currentTDD: inputs.tddLast24Hours,
            past2hoursAverage: inputs.tddLast24Hours,
            date: Date(),
            overridePercentage: override?.percentage ?? 100,
            useOverride: override != nil,
            duration: 0,
            unlimited: true,
            overrideTarget: override?.target ?? 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: override?.adjustsSensitivity ?? false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 0,
            uamMinutes: 0
        )
    }
}
