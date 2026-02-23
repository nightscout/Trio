import Foundation

// MARK: - Meal Entry Source

/// Distinguishes how the meal macros were entered for export filtering.
enum MealEntrySource: String, Codable, CaseIterable, Identifiable {
    /// User selected a Cronometer-detected meal (SmartSense flow)
    case smartSense = "smart_sense"
    /// User manually typed carbs/fat/protein
    case manual = "manual"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smartSense: return "Smart Sense"
        case .manual: return "Manual"
        }
    }
}

// MARK: - Dose-Time Snapshot (saved when user taps Add)

struct MealDecisionSnapshot: Codable {
    let id: UUID
    let doseTimestamp: Date

    // How the meal was entered
    let mealSource: MealEntrySource

    // Selected Cronometer meal (empty for manual entries)
    let selectedMeals: [MealDecisionExport.MealExportEntry]

    // Combined macros entered for dosing
    let totalCarbs: Double
    let totalFat: Double
    let totalProtein: Double

    // BG state at dose
    let currentBG: Double
    let deltaBG: Double
    let bgDirection: String?

    // Algorithm state
    let iob: Double
    let cob: Int
    let eventualBG: Double
    let minPredBG: Double
    let sensitivityRatio: Double

    // Pump settings at dose time
    let isf: Double
    let carbRatio: Double
    let target: Double
    let basalRate: Double
    let maxBolus: Double
    let maxIOB: Double

    // Calculator breakdown
    let targetDifference: Double
    let targetDifferenceInsulin: Double
    let carbInsulin: Double
    let iobReduction: Double
    let trendInsulin: Double
    let wholeCalc: Double
    let factoredInsulin: Double
    let recommended: Double
    let fattyMealEnabled: Bool
    let superBolusEnabled: Bool
    let fraction: Double

    // Delivery
    let userConfirmedDose: Double
    let isExternalInsulin: Bool
    let note: String?

    // SmartSense context
    let smartSenseResult: SmartSenseResult?
    let smartSenseOverride: Double?
}

// MARK: - Full Export (built at export time with post-meal traces)

struct MealDecisionFullExport: Codable {
    let exportDate: Date
    let rangeDays: Int
    let settings: SmartSenseSettings
    let records: [MealDecisionRecord]
}

struct MealDecisionRecord: Codable {
    let snapshot: MealDecisionSnapshot

    // Post-meal traces (queried from Core Data at export time)
    let preMealBGTrace: [BGPoint]    // 2h before dose
    let postMealBGTrace: [BGPoint]   // dose to +8h
    let bolusEvents: [BolusPoint]    // all boluses in window
    let tempBasalEvents: [TempBasalPoint]
    let loopDecisions: [LoopDecisionPoint]

    // Summary stats (computed at export)
    let summary: MealOutcomeSummary?
}

// MARK: - Post-Meal Data Points

struct BGPoint: Codable {
    let minutesAfterDose: Double
    let glucose: Int
    let direction: String?
}

struct BolusPoint: Codable {
    let minutesAfterDose: Double
    let amount: Double
    let isSMB: Bool
    let isExternal: Bool
}

struct TempBasalPoint: Codable {
    let minutesAfterDose: Double
    let rate: Double
    let durationMinutes: Int
}

struct LoopDecisionPoint: Codable {
    let minutesAfterDose: Double
    let glucose: Double
    let iob: Double
    let cob: Int
    let eventualBG: Double
    let insulinReq: Double
    let smbDelivered: Double
    let tempBasalRate: Double?
    let sensitivityRatio: Double
}

// MARK: - Meal Outcome Summary

struct MealOutcomeSummary: Codable {
    let carbsEntered: Double
    let recommendedDose: Double
    let userDose: Double
    let totalInsulinDelivered: Double
    let bgAtDose: Int
    let peakBG: Int?
    let peakMinutes: Int?
    let nadirBG: Int?
    let nadirMinutes: Int?
    let bgAt2h: Int?
    let bgAt4h: Int?
    let timeAbove180Minutes: Int
    let timeBelow70Minutes: Int
}
