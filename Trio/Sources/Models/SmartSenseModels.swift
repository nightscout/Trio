import Foundation

// MARK: - SmartSense Settings (persisted in TrioSettings)

struct SmartSenseSettings: JSON, Equatable {
    var enabled: Bool = false
    var garminEnabled: Bool = false

    /// Master split: fraction of total adjustment attributed to Garmin (0.0–1.0).
    /// Autosens gets (1 - garminSplit).
    var garminSplit: Double = 0.60

    /// Maximum sensitivity adjustment (symmetric). +-20% = 0.20.
    var maxAdjustment: Double = 0.20

    /// Per-dose override duration in hours.
    var overrideDurationHours: Double = 6.0

    /// Factor weights — must sum to 1.0.
    var weights: SmartSenseWeights = SmartSenseWeights()
}

extension SmartSenseSettings: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = SmartSenseSettings()
        if let v = try? container.decode(Bool.self, forKey: .enabled) { settings.enabled = v }
        if let v = try? container.decode(Bool.self, forKey: .garminEnabled) { settings.garminEnabled = v }
        if let v = try? container.decode(Double.self, forKey: .garminSplit) { settings.garminSplit = v }
        if let v = try? container.decode(Double.self, forKey: .maxAdjustment) { settings.maxAdjustment = v }
        if let v = try? container.decode(Double.self, forKey: .overrideDurationHours) { settings.overrideDurationHours = v }
        if let v = try? container.decode(SmartSenseWeights.self, forKey: .weights) { settings.weights = v }
        self = settings
    }
}

// MARK: - Factor Weights

struct SmartSenseWeights: JSON, Equatable {
    var sleepScore: Double = 0.30
    var sleepDuration: Double = 0.10
    var bodyBattery: Double = 0.15
    var currentStress: Double = 0.05
    var avgStress: Double = 0.05
    var restingHRDelta: Double = 0.05
    var hrvDelta: Double = 0.05
    var yesterdayActivity: Double = 0.20
    var todayActivity: Double = 0.025
    var vigorousExercise: Double = 0.025

    /// Sum of all weights — should be 1.0.
    var total: Double {
        sleepScore + sleepDuration + bodyBattery + currentStress + avgStress +
            restingHRDelta + hrvDelta + yesterdayActivity + todayActivity + vigorousExercise
    }

    /// All factor keys in display order.
    static let allFactors: [FactorKey] = [
        .sleepScore, .sleepDuration, .bodyBattery, .currentStress, .avgStress,
        .restingHRDelta, .hrvDelta, .yesterdayActivity, .todayActivity, .vigorousExercise
    ]

    enum FactorKey: String, CaseIterable, Identifiable, Codable {
        case sleepScore, sleepDuration, bodyBattery, currentStress, avgStress
        case restingHRDelta, hrvDelta, yesterdayActivity, todayActivity, vigorousExercise

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .sleepScore: return "Sleep Quality"
            case .sleepDuration: return "Sleep Duration"
            case .bodyBattery: return "Body Battery"
            case .currentStress: return "Stress (Current)"
            case .avgStress: return "Stress (Average)"
            case .restingHRDelta: return "Resting HR Delta"
            case .hrvDelta: return "HRV Delta"
            case .yesterdayActivity: return "Yesterday Activity"
            case .todayActivity: return "Today Activity"
            case .vigorousExercise: return "Vigorous Exercise"
            }
        }

        var icon: String {
            switch self {
            case .sleepScore, .sleepDuration: return "moon.zzz.fill"
            case .bodyBattery: return "battery.75percent"
            case .currentStress, .avgStress: return "brain.head.profile"
            case .restingHRDelta: return "heart.fill"
            case .hrvDelta: return "waveform.path.ecg"
            case .yesterdayActivity, .todayActivity: return "figure.run"
            case .vigorousExercise: return "flame.fill"
            }
        }
    }

    subscript(key: FactorKey) -> Double {
        get {
            switch key {
            case .sleepScore: return sleepScore
            case .sleepDuration: return sleepDuration
            case .bodyBattery: return bodyBattery
            case .currentStress: return currentStress
            case .avgStress: return avgStress
            case .restingHRDelta: return restingHRDelta
            case .hrvDelta: return hrvDelta
            case .yesterdayActivity: return yesterdayActivity
            case .todayActivity: return todayActivity
            case .vigorousExercise: return vigorousExercise
            }
        }
        set {
            switch key {
            case .sleepScore: sleepScore = newValue
            case .sleepDuration: sleepDuration = newValue
            case .bodyBattery: bodyBattery = newValue
            case .currentStress: currentStress = newValue
            case .avgStress: avgStress = newValue
            case .restingHRDelta: restingHRDelta = newValue
            case .hrvDelta: hrvDelta = newValue
            case .yesterdayActivity: yesterdayActivity = newValue
            case .todayActivity: todayActivity = newValue
            case .vigorousExercise: vigorousExercise = newValue
            }
        }
    }
}

extension SmartSenseWeights: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var w = SmartSenseWeights()
        if let v = try? container.decode(Double.self, forKey: .sleepScore) { w.sleepScore = v }
        if let v = try? container.decode(Double.self, forKey: .sleepDuration) { w.sleepDuration = v }
        if let v = try? container.decode(Double.self, forKey: .bodyBattery) { w.bodyBattery = v }
        if let v = try? container.decode(Double.self, forKey: .currentStress) { w.currentStress = v }
        if let v = try? container.decode(Double.self, forKey: .avgStress) { w.avgStress = v }
        if let v = try? container.decode(Double.self, forKey: .restingHRDelta) { w.restingHRDelta = v }
        if let v = try? container.decode(Double.self, forKey: .hrvDelta) { w.hrvDelta = v }
        if let v = try? container.decode(Double.self, forKey: .yesterdayActivity) { w.yesterdayActivity = v }
        if let v = try? container.decode(Double.self, forKey: .todayActivity) { w.todayActivity = v }
        if let v = try? container.decode(Double.self, forKey: .vigorousExercise) { w.vigorousExercise = v }
        self = w
    }
}

// MARK: - SmartSense Computation Results

/// Result of computing the full SmartSense sensitivity pipeline.
struct SmartSenseResult: Codable {
    /// Individual Garmin factor contributions.
    let garminFactors: [FactorContribution]

    /// Garmin composite adjustment (sum of weighted impacts), e.g. +0.12 = +12%.
    let garminComposite: Double

    /// Autosens ratio from oref (e.g. 1.04 = 4% more resistant).
    let autosensRatio: Double

    /// Autosens contribution as adjustment (autosensRatio - 1.0), e.g. +0.04.
    let autosensContribution: Double

    /// Master split used.
    let masterSplit: MasterSplit

    /// Blended suggestion before user override, e.g. +0.088.
    let blendedSuggestion: Double

    /// Final ratio after blending and clamping, e.g. 1.09.
    var finalRatio: Double

    /// Whether Garmin data was available.
    let garminDataAvailable: Bool

    /// Timestamp of the Garmin data used.
    let garminDataTime: Date?

    struct FactorContribution: Codable {
        let factor: String
        let value: String
        let rawImpact: Double
        let weight: Double
        let weightedImpact: Double
    }

    struct MasterSplit: Codable {
        let garmin: Double
        let autosens: Double
    }
}

// MARK: - Per-Dose Override

/// Tracks a user's sensitivity override applied at dose time.
struct SmartSenseOverride: Codable {
    let overrideRatio: Double
    let computedRatio: Double
    let wasModified: Bool
    let appliedAt: Date
    let expiresAt: Date

    var isActive: Bool {
        Date() < expiresAt
    }
}

// MARK: - Detected Meal (from Cronometer via HealthKit)

struct DetectedMeal: Identifiable, Codable, Equatable {
    let id: UUID
    let detectedAt: Date
    let carbs: Double
    let fat: Double
    let protein: Double
    let fiber: Double
    let source: String // e.g. "cronometer"
    var isDosed: Bool

    /// Label for display (time-based)
    var label: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Meal at \(formatter.string(from: detectedAt))"
    }
}

// MARK: - Meal Decision Export

struct MealDecisionExport: Codable {
    let mealTimestamp: Date
    let doseTimestamp: Date
    let delayMinutes: Int

    let selectedMeals: [MealExportEntry]

    let stateAtDose: DoseState
    let smartSense: SmartSenseResult
    let userOverride: Double?
    let overrideWasModified: Bool

    let dose: DoseExport

    struct MealExportEntry: Codable {
        let label: String
        let carbs: Double
        let fat: Double
        let protein: Double
        let fiber: Double
        let source: String
        let detectedAt: Date
    }

    struct DoseState: Codable {
        let currentBG: Double?
        let bgAtMealDetection: Double?
        let bgRiseSinceMeal: Double?
        let iobAtDose: Double?
        let cobAtDose: Double?
        let estimatedAbsorbed: Double?
    }

    struct DoseExport: Codable {
        let recommended: Double
        let delivered: Double
        let preDoseIOB: Double
        let preDoseCOB: Double
    }
}
