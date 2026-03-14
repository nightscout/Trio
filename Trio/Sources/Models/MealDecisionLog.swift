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
    let toughMealEnabled: Bool
    let toughMealAutoDetected: Bool
    let toughMealGateReason: String
    let fatPlusProteinGrams: Double
    let fraction: Double

    // Delivery
    let userConfirmedDose: Double
    let isExternalInsulin: Bool
    let note: String?

    // SmartSense context
    let smartSenseResult: SmartSenseResult?
    let smartSenseOverride: Double?

    // Signal pipeline state at dose time (Phase 1)
    let signalSmoothedBG: Double?
    let signalVelocity: Double?
    let signalAcceleration: Double?
    let signalJerk: Double?
    let signalResidual: Double?
    let signalMealDetection: String?
}

// MARK: - Full Export (built at export time with post-meal traces)

struct MealDecisionFullExport: Codable {
    let exportDate: Date
    let rangeDays: Int
    let settings: SmartSenseSettings
    let records: [MealDecisionRecord]

    // Daily Garmin Z-score history for the export range (Phase 1)
    let dailyZScores: [DailyZScoreExport]?
}

// MARK: - Daily Z-Score Export

struct DailyZScoreExport: Codable {
    let date: Date
    let hrvZScore: Double?
    let restingHRZScore: Double?
    let sleepScoreZScore: Double?
    let sleepDurationZScore: Double?
    let deepSleepZScore: Double?
    let bodyBatteryZScore: Double?
    let stressConfidence: String
    let baselineSize: Int
    let hrvRMSSD: Double?
    let restingHR: Double?
    let sleepScore: Double?
    let sleepDurationMinutes: Double?
}

struct MealDecisionRecord: Codable {
    let snapshot: MealDecisionSnapshot

    // Post-meal traces (queried from Core Data at export time)
    let preMealBGTrace: [BGPoint]    // 2h before dose
    let postMealBGTrace: [BGPoint]   // dose to +8h
    let bolusEvents: [BolusPoint]    // all boluses in window
    let tempBasalEvents: [TempBasalPoint]
    let loopDecisions: [LoopDecisionPoint]

    // Signal pipeline trace (from signal log, matched to meal window)
    let signalTrace: [SignalTracePoint]?

    // Summary stats (computed at export)
    let summary: MealOutcomeSummary?
}

// MARK: - Signal Trace Point (from Phase 1 signal pipeline)

struct SignalTracePoint: Codable {
    let minutesAfterDose: Double
    let rawBG: Double
    let smoothedBG: Double
    let velocity: Double
    let acceleration: Double
    let jerk: Double?
    let bgUncertainty: Double
    let residual: Double?
    let residualRate: Double?
    let carbAbsorptionRate: Double?
    let mealDetection: String
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

    // Signal pipeline data (Phase 1)
    let smoothedBG: Double?
    let bgVelocity: Double?           // mg/dL per minute
    let bgAcceleration: Double?       // mg/dL per minute²
    let bgJerk: Double?               // mg/dL per minute³
    let bgResidual: Double?           // actual - expected (from IOB)
    let residualRate: Double?         // mg/dL per minute
    let carbAbsorptionRate: Double?   // g/min estimated from residual
    let mealDetection: String?        // none/possible/likely/confirmed
}

// MARK: - Standalone Signal Pipeline Export

struct SignalPipelineExport: Codable {
    let exportDate: Date
    let rangeDays: Int
    let signalCount: Int
    let zScoreCount: Int
    let signals: [SignalStore.SignalEntry]
    let dailyZScores: [SignalStore.DailyZScoreEntry]
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
