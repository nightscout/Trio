import ClockKit
import Foundation

/// Shared data structure for complication glucose display
struct ComplicationData: Codable {
    let glucose: String
    let trend: String
    let delta: String
    let glucoseDate: Date?
    let lastLoopDate: Date?
    let iob: String?
    let cob: String?
    let eventualBG: String?

    static let userDefaultsKey = "complicationData"

    /// Save complication data to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
    }

    /// Load complication data from UserDefaults
    static func load() -> ComplicationData? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(ComplicationData.self, from: data) else {
            return nil
        }
        return decoded
    }

    /// Extract numeric glucose value for comparison (returns nil if not parseable)
    var numericGlucose: Double? {
        // Handle both mg/dL (integer) and mmol/L (decimal) formats
        Double(glucose.replacingOccurrences(of: ",", with: "."))
    }

    /// Check if glucose data is stale (older than 15 minutes)
    var isStale: Bool {
        guard let date = glucoseDate else { return true }
        return Date().timeIntervalSince(date) > 15 * 60
    }

    /// Check if glucose data is very stale (older than 30 minutes)
    var isVeryStale: Bool {
        guard let date = glucoseDate else { return true }
        return Date().timeIntervalSince(date) > 30 * 60
    }

    /// Minutes since last glucose reading
    var minutesAgo: Int {
        guard let date = glucoseDate else { return 999 }
        return Int(Date().timeIntervalSince(date) / 60)
    }

    /// Color representation based on staleness
    var staleColor: String {
        if isVeryStale { return "red" }
        if isStale { return "yellow" }
        return "green"
    }

    /// Formatted glucose with trend for display
    var glucoseWithTrend: String {
        "\(glucose) \(trend)"
    }

    /// Formatted glucose with trend and delta
    var fullDisplay: String {
        "\(glucose) \(trend) \(delta)"
    }
}

// MARK: - Smart Complication Update Manager

/// Manages complication updates using a smart algorithm to maximize the ~50 daily budget
/// Based on Loop's approach: https://github.com/LoopKit/Loop/issues/816
///
/// Update Strategy:
/// 1. If glucose is in safe range (90-120 mg/dL) AND was already in range → NO update (save budget)
/// 2. If glucose crosses INTO or OUT OF safe range → IMMEDIATE update
/// 3. If glucose is out of range → use time/change thresholds
final class ComplicationUpdateManager {
    static let shared = ComplicationUpdateManager()

    // MARK: - Configuration

    /// Safe glucose range where updates are skipped entirely (mg/dL)
    private let safeRangeLowMgdl: Double = 90.0
    private let safeRangeHighMgdl: Double = 120.0

    /// Safe glucose range for mmol/L users (5.0 - 6.7 mmol/L)
    private let safeRangeLowMmol: Double = 5.0
    private let safeRangeHighMmol: Double = 6.7

    /// Minimum time between budgeted updates when OUT of safe range (default: 20 minutes)
    private let minimumUpdateInterval: TimeInterval = 20 * 60

    /// Glucose change threshold to trigger immediate update when out of range (mg/dL)
    private let significantGlucoseChange: Double = 20.0

    /// Equivalent threshold for mmol/L users (~1.1 mmol/L)
    private let significantGlucoseChangeMmol: Double = 1.1

    // MARK: - Tracking Keys

    private let lastBudgetedUpdateKey = "complication.lastBudgetedUpdate"
    private let lastBudgetedGlucoseKey = "complication.lastBudgetedGlucose"
    private let dailyUpdateCountKey = "complication.dailyUpdateCount"
    private let updateCountDateKey = "complication.updateCountDate"
    private let wasInSafeRangeKey = "complication.wasInSafeRange"

    // MARK: - State

    private var lastBudgetedUpdateTime: Date? {
        get { UserDefaults.standard.object(forKey: lastBudgetedUpdateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastBudgetedUpdateKey) }
    }

    private var lastBudgetedGlucose: Double? {
        get { UserDefaults.standard.object(forKey: lastBudgetedGlucoseKey) as? Double }
        set { UserDefaults.standard.set(newValue, forKey: lastBudgetedGlucoseKey) }
    }

    private var wasInSafeRange: Bool {
        get { UserDefaults.standard.bool(forKey: wasInSafeRangeKey) }
        set { UserDefaults.standard.set(newValue, forKey: wasInSafeRangeKey) }
    }

    private var dailyUpdateCount: Int {
        get {
            // Reset count if it's a new day
            if let countDate = UserDefaults.standard.object(forKey: updateCountDateKey) as? Date,
               !Calendar.current.isDateInToday(countDate) {
                UserDefaults.standard.set(0, forKey: dailyUpdateCountKey)
                UserDefaults.standard.set(Date(), forKey: updateCountDateKey)
            }
            return UserDefaults.standard.integer(forKey: dailyUpdateCountKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: dailyUpdateCountKey)
            UserDefaults.standard.set(Date(), forKey: updateCountDateKey)
        }
    }

    // MARK: - Public Interface

    /// Determines if a budgeted complication update should be used
    /// Always saves data, but only triggers reload when worthwhile
    func updateComplications(with data: ComplicationData) {
        // Always save the latest data (for timeline-based refreshes)
        data.save()

        // Check if we should use a budgeted update
        if shouldUseBudgetedUpdate(for: data) {
            performBudgetedUpdate(with: data)
        } else {
            // Use timeline extension instead (doesn't count against budget)
            ComplicationUpdateHelper.extendAllComplications()
        }

        // Track safe range state for next comparison
        if let glucose = data.numericGlucose {
            wasInSafeRange = isInSafeRange(glucose)
        }
    }

    /// Force an immediate update (use sparingly - counts against budget)
    func forceUpdate() {
        ComplicationUpdateHelper.reloadAllComplications()
        lastBudgetedUpdateTime = Date()
        dailyUpdateCount += 1
    }

    /// Get current budget status for debugging/display
    var budgetStatus: String {
        let remaining = max(0, 50 - dailyUpdateCount)
        return "Updates today: \(dailyUpdateCount)/50 (\(remaining) remaining)"
    }

    // MARK: - Safe Range Helpers

    /// Check if glucose value is in the safe range (90-120 mg/dL or 5.0-6.7 mmol/L)
    private func isInSafeRange(_ glucose: Double) -> Bool {
        // Detect unit based on value range
        if glucose < 30 {
            // mmol/L
            return glucose >= safeRangeLowMmol && glucose <= safeRangeHighMmol
        } else {
            // mg/dL
            return glucose >= safeRangeLowMgdl && glucose <= safeRangeHighMgdl
        }
    }

    /// Check if glucose crossed the safe range boundary
    private func crossedSafeRangeBoundary(_ currentGlucose: Double) -> Bool {
        let currentlyInRange = isInSafeRange(currentGlucose)
        // Crossed if current state differs from previous state
        return currentlyInRange != wasInSafeRange
    }

    // MARK: - Private Methods

    private func shouldUseBudgetedUpdate(for data: ComplicationData) -> Bool {
        guard let currentGlucose = data.numericGlucose else {
            // Can't parse glucose, use budgeted update to be safe
            return dailyUpdateCount < 50
        }

        let now = Date()
        let budgetAvailable = dailyUpdateCount < 50

        guard budgetAvailable else { return false }

        // RULE 1: If crossing safe range boundary, always update immediately
        if crossedSafeRangeBoundary(currentGlucose) {
            #if DEBUG
            let direction = isInSafeRange(currentGlucose) ? "INTO" : "OUT OF"
            print("🎯 Glucose crossed \(direction) safe range → immediate update")
            #endif
            return true
        }

        // RULE 2: If currently in safe range (and was in safe range), skip budgeted update
        if isInSafeRange(currentGlucose) && wasInSafeRange {
            #if DEBUG
            print("😴 Glucose in safe range (90-120) → skipping budgeted update")
            #endif
            return false
        }

        // RULE 3: Out of safe range - use time/change thresholds

        // Time condition: enough time has passed since last budgeted update
        let timeCondition: Bool
        if let lastUpdate = lastBudgetedUpdateTime {
            timeCondition = now.timeIntervalSince(lastUpdate) >= minimumUpdateInterval
        } else {
            timeCondition = true
        }

        // Change condition: significant glucose change since last update
        let glucoseCondition: Bool
        if let previousGlucose = lastBudgetedGlucose {
            let change = abs(currentGlucose - previousGlucose)
            let threshold = currentGlucose < 30 ? significantGlucoseChangeMmol : significantGlucoseChange
            glucoseCondition = change >= threshold
        } else {
            glucoseCondition = true
        }

        return timeCondition || glucoseCondition
    }

    private func performBudgetedUpdate(with data: ComplicationData) {
        ComplicationUpdateHelper.reloadAllComplications()

        // Track this update
        lastBudgetedUpdateTime = Date()
        if let glucose = data.numericGlucose {
            lastBudgetedGlucose = glucose
        }
        dailyUpdateCount += 1

        #if DEBUG
        print("🔄 Complication budgeted update #\(dailyUpdateCount): \(data.glucose) \(data.trend)")
        #endif
    }
}

// MARK: - Complication Update Helper

enum ComplicationUpdateHelper {
    /// Reload all active complications (uses budget)
    static func reloadAllComplications() {
        let server = CLKComplicationServer.sharedInstance()
        guard let activeComplications = server.activeComplications else { return }

        for complication in activeComplications {
            server.reloadTimeline(for: complication)
        }
    }

    /// Extend timeline for all active complications (does not use budget)
    static func extendAllComplications() {
        let server = CLKComplicationServer.sharedInstance()
        guard let activeComplications = server.activeComplications else { return }

        for complication in activeComplications {
            server.extendTimeline(for: complication)
        }
    }
}
