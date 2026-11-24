import Foundation
import SwiftUI

/// Prototype: advice wording is fixed per scenario and not clinically validated.
enum SettingsAnalysis {}

// MARK: - Scenarios

extension SettingsAnalysis {
    enum Scenario: String, CaseIterable, Identifiable, Hashable {
        case mealSpike
        case bolusThenHypo
        case dawnPhenomenon
        case overnightLow
        case persistentHigh
        case delayedMealRise
        case exerciseDrop
        case unannouncedMeal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mealSpike: return String(localized: "Post-Meal Spike")
            case .bolusThenHypo: return String(localized: "Bolus Then Hypo")
            case .dawnPhenomenon: return String(localized: "Dawn Phenomenon")
            case .overnightLow: return String(localized: "Overnight Low")
            case .persistentHigh: return String(localized: "Persistent High")
            case .delayedMealRise: return String(localized: "Delayed Meal Rise")
            case .exerciseDrop: return String(localized: "Activity Drop")
            case .unannouncedMeal: return String(localized: "Unannounced Meal Rise")
            }
        }

        var icon: String {
            switch self {
            case .mealSpike: return "fork.knife"
            case .bolusThenHypo: return "arrow.down.right"
            case .dawnPhenomenon: return "sunrise"
            case .overnightLow: return "moon.zzz"
            case .persistentHigh: return "arrow.up.to.line"
            case .delayedMealRise: return "clock.arrow.circlepath"
            case .exerciseDrop: return "figure.run"
            case .unannouncedMeal: return "takeoutbag.and.cup.and.straw"
            }
        }

        var color: Color {
            switch self {
            case .bolusThenHypo,
                 .exerciseDrop,
                 .overnightLow: return .red
            case .delayedMealRise,
                 .mealSpike,
                 .persistentHigh,
                 .unannouncedMeal: return .orange
            case .dawnPhenomenon: return .yellow
            }
        }

        var summary: String {
            switch self {
            case .mealSpike:
                return String(
                    localized: "Glucose rises sharply in the first two hours after a meal, even though carbs were entered and bolused."
                )
            case .bolusThenHypo:
                return String(
                    localized: "A low follows within a few hours of a meal or correction bolus. Often a sign of too much insulin for the carbs or the correction."
                )
            case .dawnPhenomenon:
                return String(
                    localized: "Glucose rises in the early morning without any carbs, driven by hormones released before waking."
                )
            case .overnightLow:
                return String(localized: "Glucose drops below range during the night, often hours after the last bolus.")
            case .persistentHigh:
                return String(
                    localized: "Glucose stays high for hours and does not respond as expected to insulin. Can be settings, but also a failing infusion site or illness."
                )
            case .delayedMealRise:
                return String(
                    localized: "Glucose looks fine after a meal, then rises three to six hours later. Typical for high-fat or high-protein meals."
                )
            case .exerciseDrop:
                return String(
                    localized: "Glucose drops quickly during or after physical activity while insulin on board is still high."
                )
            case .unannouncedMeal:
                return String(
                    localized: "Glucose rises fast like after a meal, but no carbs were logged, and goes above range. Covers meals left fully to UAM and meals with only a manual prebolus."
                )
            }
        }

        /// Scenarios that start from a carb entry and can't be checked without logged meals.
        var requiresCarbEntries: Bool {
            switch self {
            case .delayedMealRise,
                 .mealSpike: return true
            default: return false
            }
        }

        /// Keep in sync with `SettingsAnalysis.Detectors`.
        func detectionRule(units: GlucoseUnits) -> String {
            typealias Threshold = Detectors.Threshold
            let low = Threshold.low.formatted(withUnits: units)
            let high = Threshold.high.formatted(withUnits: units)
            let rise = Threshold.mealRise.formatted(withUnits: units)
            let drop = Threshold.activityDrop.formatted(withUnits: units)
            let dawnRise = Threshold.dawnRise.formatted(withUnits: units)
            let fastRise = Threshold.unannouncedRise.formatted(withUnits: units)

            switch self {
            case .mealSpike:
                return String(localized: "Carb entry, then a rise of more than \(rise) to above \(high) within 2 h.")
            case .bolusThenHypo:
                return String(
                    localized: "Manual bolus, or SMBs after an unannounced meal, then glucose below \(low) within 4 h, with no carbs in between."
                )
            case .dawnPhenomenon:
                return String(
                    localized: "Rise of more than \(dawnRise) between 03:00 and 08:00 with no low that night. The window ends at the first carbs, bolus or unannounced meal."
                )
            case .overnightLow:
                return String(localized: "Glucose below \(low) between 00:00 and 06:00.")
            case .persistentHigh:
                return String(localized: "Glucose above \(high) for more than 3 h without carbs or an unannounced meal.")
            case .delayedMealRise:
                return String(localized: "In range 2 h after a meal, then above \(high) 3–6 h after it.")
            case .exerciseDrop:
                return String(
                    localized: "Drop of more than \(drop) within 1 h, during a raised temp target or a reduced-insulin override, or the hour after it. Temp targets and overrides set during a low or within 30 min after it, and those you turn off before analyzing, are not counted."
                )
            case .unannouncedMeal:
                return String(
                    localized: "Rise of more than \(fastRise) within 30 min with no carbs logged, then above \(high) within 2 h. A manual bolus up to 1 h before counts as a prebolus."
                )
            }
        }
    }
}

// MARK: - Time frames

extension SettingsAnalysis {
    enum TimeFramePreset: String, CaseIterable, Identifiable {
        case week
        case twoWeeks
        case threeMonths

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .week: return String(localized: "1 Week")
            case .twoWeeks: return String(localized: "2 Weeks")
            case .threeMonths: return String(localized: "3 Months")
            }
        }

        var days: Int {
            switch self {
            case .week: return 7
            case .twoWeeks: return 14
            case .threeMonths: return 90
            }
        }
    }

    struct TimeFrame: Hashable {
        let start: Date
        let end: Date

        var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
        var days: Double { duration / 86400 }
        var isValid: Bool { end > start }

        static func preset(_ preset: TimeFramePreset, now: Date = Date()) -> TimeFrame {
            TimeFrame(start: now.addingTimeInterval(-Double(preset.days) * 86400), end: now)
        }

        var formatted: String {
            let style = Date.FormatStyle(date: .abbreviated, time: days < 3 ? .shortened : .omitted)
            return "\(start.formatted(style)) – \(end.formatted(style))"
        }
    }
}

// MARK: - Results

extension SettingsAnalysis {
    enum Severity: Int, Comparable {
        case low
        case moderate
        case high

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        var displayName: String {
            switch self {
            case .low: return String(localized: "Occasional")
            case .moderate: return String(localized: "Frequent")
            case .high: return String(localized: "Very Frequent")
            }
        }

        var color: Color {
            switch self {
            case .low: return .green
            case .moderate: return .orange
            case .high: return .red
            }
        }
    }

    enum Confidence: Int {
        case low
        case medium
        case high

        var displayName: String {
            switch self {
            case .low: return String(localized: "Low confidence")
            case .medium: return String(localized: "Medium confidence")
            case .high: return String(localized: "High confidence")
            }
        }

        var bars: Int { rawValue + 1 }
    }

    struct Occurrence: Identifiable {
        let id = UUID()
        let date: Date
        let detail: String
    }

    struct Advice: Identifiable {
        let id = UUID()
        /// The setting or behaviour the advice targets, e.g. "Carb Ratio 06:00–10:00".
        let target: String
        let recommendation: String
        let rationale: String
        let confidence: Confidence
    }

    struct Finding: Identifiable {
        var id: Scenario { scenario }
        let scenario: Scenario
        let occurrences: [Occurrence]
        let count: Int
        let perWeek: Double
        let severity: Severity
        /// e.g. "64% after breakfast".
        let pattern: String
        let advice: Advice
        /// Guards that lowered this finding's confidence.
        let guardIDs: [String]
    }

    struct UnavailableScenario: Identifiable {
        var id: Scenario { scenario }
        let scenario: Scenario
        let reason: String
    }

    struct Report {
        let timeFrame: TimeFrame
        let checks: SettingsCheckReport?
        let catalog: Catalog?
        let catalogError: String?
        let findings: [Finding]
        let notDetected: [Scenario]
        /// Scenarios that could not be checked, e.g. carb-based ones without logged meals.
        let unavailable: [UnavailableScenario]
        let mealProfile: MealProfile
        let generatedAt: Date
        /// Percent of readings in 70–180 mg/dL, or nil without readings.
        let timeInRange: Int?
        let readings: Int
        /// Readings a CGM at 5-minute intervals would have produced.
        let expectedReadings: Int

        /// Share of the time frame covered by CGM readings, 0–100.
        var coverage: Int {
            guard expectedReadings > 0 else { return 0 }
            return min(Int((Double(readings) / Double(expectedReadings) * 100).rounded()), 100)
        }
    }
}
