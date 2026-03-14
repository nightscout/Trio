import Foundation

/// Phase 4: Post-Exercise Sensitivity Modeling
///
/// Applies time-decaying ISF/CR modifiers based on Garmin activity data.
/// Classifies exercise type from intensity metrics and applies appropriate
/// post-exercise sensitivity curves.
///
/// When the toggle is OFF, computes and logs but doesn't modify oref parameters.
///
/// Reference: oref improvements §6.3, §6.4

final class ExerciseSensitivityModel {
    // MARK: - Configuration

    struct Config {
        // Aerobic exercise: enhances sensitivity after completion
        /// Peak ISF boost for moderate aerobic (fraction, e.g. 0.25 = +25%)
        var aerobicPeakISFBoost: Double = 0.25
        /// Hours after workout when peak sensitivity occurs
        var aerobicPeakHours: Double = 3.0
        /// Hours until sensitivity returns to baseline
        var aerobicDecayHours: Double = 24.0

        // Anaerobic exercise: brief resistance then enhanced sensitivity
        /// Acute resistance phase ISF reduction
        var anaerobicAcuteResistance: Double = -0.10
        /// Hours of acute resistance
        var anaerobicResistanceHours: Double = 1.0
        /// Peak ISF boost after resistance phase clears
        var anaerobicPeakISFBoost: Double = 0.20
        /// Hours after workout when sensitivity peaks
        var anaerobicPeakHours: Double = 4.0
        /// Hours until return to baseline
        var anaerobicDecayHours: Double = 18.0

        // Glycogen depletion
        /// Active calories threshold for moderate depletion
        var moderateDepletionCalories: Double = 400.0
        /// Active calories threshold for significant depletion
        var significantDepletionCalories: Double = 600.0
        /// CR modifier for moderate depletion (e.g. 1.2 = need 20% more carbs per unit)
        var moderateDepletionCRModifier: Double = 1.2
        /// CR modifier for significant depletion
        var significantDepletionCRModifier: Double = 1.4
        /// Hours after workout that depletion effect persists
        var depletionDurationHours: Double = 6.0

        // Intensity thresholds (minutes)
        var vigorousMinutesForAnaerobic: Double = 20.0
        var moderateMinutesForAerobic: Double = 30.0
    }

    // MARK: - Exercise Classification

    enum ExerciseType: String, Codable {
        case aerobic = "aerobic"         // Endurance: running, cycling, swimming
        case anaerobic = "anaerobic"     // Strength, HIIT, sprints
        case mixed = "mixed"             // Both significant
        case light = "light"             // Light activity, not significant
        case none = "none"               // No meaningful exercise
    }

    enum GlycogenState: String, Codable {
        case normal = "normal"
        case moderatelyDepleted = "moderately_depleted"
        case significantlyDepleted = "significantly_depleted"
    }

    // MARK: - Output

    struct ExerciseOutput: Codable {
        let timestamp: Date

        // Yesterday's exercise classification
        let yesterdayExerciseType: String
        let yesterdayActiveCalories: Int?
        let yesterdayVigorousMinutes: Int?
        let yesterdayModerateMinutes: Int?

        // Today's exercise classification
        let todayExerciseType: String
        let todayActiveCalories: Int?
        let todayVigorousMinutes: Int?

        // Computed modifiers (shadow mode values)
        let postExerciseISFModifier: Double   // From yesterday's exercise
        let todayActivityISFModifier: Double   // From today's ongoing activity
        let netISFModifier: Double             // Combined
        let crModifier: Double                 // Glycogen depletion effect
        let glycogenState: String

        // Where we are in the post-exercise window
        let hoursSinceYesterdayExercise: Double?
        let exerciseSensitivityWindowActive: Bool

        // Explanation
        let explanation: String
    }

    // MARK: - State

    private var config: Config
    private(set) var latestOutput: ExerciseOutput?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Compute

    /// Compute exercise sensitivity modifiers from Garmin activity data.
    func compute(
        yesterdayActiveCalories: Int?,
        yesterdayVigorousMinutes: Int?,
        yesterdayModerateMinutes: Int?,
        todayActiveCalories: Int?,
        todayVigorousMinutes: Int?,
        todayModerateMinutes: Int?,
        hoursSinceMidnight: Double = {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
            return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        }()
    ) -> ExerciseOutput {
        var explanations: [String] = []

        // Classify yesterday's exercise
        let yesterdayType = classifyExercise(
            vigorousMinutes: yesterdayVigorousMinutes,
            moderateMinutes: yesterdayModerateMinutes,
            activeCalories: yesterdayActiveCalories
        )

        // Classify today's exercise
        let todayType = classifyExercise(
            vigorousMinutes: todayVigorousMinutes,
            moderateMinutes: todayModerateMinutes,
            activeCalories: todayActiveCalories
        )

        // Post-exercise sensitivity from yesterday
        // Assume exercise ended around 6pm yesterday → hours since = hoursSinceMidnight + 6
        let estimatedHoursSinceExercise = hoursSinceMidnight + 6.0
        let postExerciseISF = computePostExerciseModifier(
            exerciseType: yesterdayType,
            hoursSinceExercise: estimatedHoursSinceExercise
        )

        if abs(postExerciseISF) > 0.01 {
            let direction = postExerciseISF > 0 ? "enhanced" : "reduced"
            explanations.append(
                "Yesterday's \(yesterdayType.rawValue) exercise → \(direction) sensitivity " +
                "(\(String(format: "%+.0f", postExerciseISF * 100))%)"
            )
        }

        // Today's ongoing activity modifier
        let todayISF = computeTodayActivityModifier(
            exerciseType: todayType,
            activeCalories: todayActiveCalories
        )

        if abs(todayISF) > 0.01 {
            explanations.append(
                "Today's activity → \(String(format: "%+.0f", todayISF * 100))% sensitivity"
            )
        }

        // Combined ISF modifier (capped at ±30%)
        let netISF = max(-0.30, min(0.30, postExerciseISF + todayISF))

        // Glycogen depletion → CR modifier
        let glycogen: GlycogenState
        let crMod: Double
        if let cal = yesterdayActiveCalories {
            if Double(cal) >= config.significantDepletionCalories,
               estimatedHoursSinceExercise < config.depletionDurationHours + 12
            {
                glycogen = .significantlyDepleted
                // Decay the CR modifier over time
                let decayFactor = max(0, 1.0 - (estimatedHoursSinceExercise / (config.depletionDurationHours + 12)))
                crMod = 1.0 + (config.significantDepletionCRModifier - 1.0) * decayFactor
                explanations.append("Glycogen significantly depleted → CR \(String(format: "%.1f", crMod))x")
            } else if Double(cal) >= config.moderateDepletionCalories,
                      estimatedHoursSinceExercise < config.depletionDurationHours + 6
            {
                glycogen = .moderatelyDepleted
                let decayFactor = max(0, 1.0 - (estimatedHoursSinceExercise / (config.depletionDurationHours + 6)))
                crMod = 1.0 + (config.moderateDepletionCRModifier - 1.0) * decayFactor
                explanations.append("Glycogen moderately depleted → CR \(String(format: "%.1f", crMod))x")
            } else {
                glycogen = .normal
                crMod = 1.0
            }
        } else {
            glycogen = .normal
            crMod = 1.0
        }

        let windowActive = abs(postExerciseISF) > 0.01 || abs(todayISF) > 0.01

        let output = ExerciseOutput(
            timestamp: Date(),
            yesterdayExerciseType: yesterdayType.rawValue,
            yesterdayActiveCalories: yesterdayActiveCalories,
            yesterdayVigorousMinutes: yesterdayVigorousMinutes,
            yesterdayModerateMinutes: yesterdayModerateMinutes,
            todayExerciseType: todayType.rawValue,
            todayActiveCalories: todayActiveCalories,
            todayVigorousMinutes: todayVigorousMinutes,
            postExerciseISFModifier: postExerciseISF,
            todayActivityISFModifier: todayISF,
            netISFModifier: netISF,
            crModifier: crMod,
            glycogenState: glycogen.rawValue,
            hoursSinceYesterdayExercise: estimatedHoursSinceExercise,
            exerciseSensitivityWindowActive: windowActive,
            explanation: explanations.isEmpty ? "No significant exercise effect" : explanations.joined(separator: "; ")
        )

        latestOutput = output
        return output
    }

    func reset() {
        latestOutput = nil
    }

    // MARK: - Private

    private func classifyExercise(
        vigorousMinutes: Int?,
        moderateMinutes: Int?,
        activeCalories: Int?
    ) -> ExerciseType {
        let vigorous = Double(vigorousMinutes ?? 0)
        let moderate = Double(moderateMinutes ?? 0)

        let hasAnaerobic = vigorous >= config.vigorousMinutesForAnaerobic
        let hasAerobic = moderate >= config.moderateMinutesForAerobic

        if hasAnaerobic && hasAerobic { return .mixed }
        if hasAnaerobic { return .anaerobic }
        if hasAerobic { return .aerobic }
        if vigorous > 5 || moderate > 10 { return .light }
        return .none
    }

    /// Compute post-exercise ISF modifier using time-decaying curves.
    /// Positive = more sensitive, negative = more resistant.
    private func computePostExerciseModifier(
        exerciseType: ExerciseType,
        hoursSinceExercise: Double
    ) -> Double {
        switch exerciseType {
        case .aerobic:
            return aerobicSensitivityCurve(hours: hoursSinceExercise)
        case .anaerobic:
            return anaerobicSensitivityCurve(hours: hoursSinceExercise)
        case .mixed:
            // Blend of both curves
            let aero = aerobicSensitivityCurve(hours: hoursSinceExercise)
            let anaero = anaerobicSensitivityCurve(hours: hoursSinceExercise)
            return (aero + anaero) / 2.0
        case .light:
            // Mild aerobic effect
            return aerobicSensitivityCurve(hours: hoursSinceExercise) * 0.3
        case .none:
            return 0
        }
    }

    /// Aerobic exercise sensitivity curve
    /// 0-0.5h: +0% (acute recovery)
    /// 0.5-peak: ramp up to peak boost
    /// peak-decay: linear decay to 0
    private func aerobicSensitivityCurve(hours: Double) -> Double {
        guard hours > 0.5 else { return 0 }
        guard hours < config.aerobicDecayHours else { return 0 }

        if hours < config.aerobicPeakHours {
            // Ramp up
            let progress = (hours - 0.5) / (config.aerobicPeakHours - 0.5)
            return config.aerobicPeakISFBoost * progress
        } else {
            // Decay
            let progress = (hours - config.aerobicPeakHours) / (config.aerobicDecayHours - config.aerobicPeakHours)
            return config.aerobicPeakISFBoost * (1 - progress)
        }
    }

    /// Anaerobic exercise sensitivity curve
    /// 0-1h: acute resistance (negative)
    /// 1-peak: ramp up through zero to positive sensitivity
    /// peak-decay: linear decay to 0
    private func anaerobicSensitivityCurve(hours: Double) -> Double {
        guard hours > 0 else { return 0 }
        guard hours < config.anaerobicDecayHours else { return 0 }

        if hours < config.anaerobicResistanceHours {
            // Acute resistance phase
            return config.anaerobicAcuteResistance
        } else if hours < config.anaerobicPeakHours {
            // Transition from resistance to sensitivity
            let progress = (hours - config.anaerobicResistanceHours) /
                (config.anaerobicPeakHours - config.anaerobicResistanceHours)
            return config.anaerobicAcuteResistance + (config.anaerobicPeakISFBoost - config.anaerobicAcuteResistance) * progress
        } else {
            // Decay from peak
            let progress = (hours - config.anaerobicPeakHours) / (config.anaerobicDecayHours - config.anaerobicPeakHours)
            return config.anaerobicPeakISFBoost * (1 - progress)
        }
    }

    /// Today's ongoing activity modifier (mild, based on current day calories)
    private func computeTodayActivityModifier(
        exerciseType: ExerciseType,
        activeCalories: Int?
    ) -> Double {
        guard let cal = activeCalories, exerciseType != .none else { return 0 }

        // Mild sensitivity boost proportional to today's activity
        if Double(cal) > 400 { return 0.10 }
        if Double(cal) > 200 { return 0.05 }
        return 0
    }
}
