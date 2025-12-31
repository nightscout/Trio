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
final class ComplicationUpdateManager {
    static let shared = ComplicationUpdateManager()

    // MARK: - Configuration

    /// Minimum time between budgeted updates (default: 20 minutes)
    /// With 50 updates/day, this allows updates every ~29 minutes
    /// We use 20 min to leave room for significant changes
    private let minimumUpdateInterval: TimeInterval = 20 * 60

    /// Glucose change threshold to trigger immediate update (mg/dL)
    /// A change of ≥20 mg/dL is considered significant
    private let significantGlucoseChange: Double = 20.0

    /// Equivalent threshold for mmol/L users (~1.1 mmol/L)
    private let significantGlucoseChangeMmol: Double = 1.1

    // MARK: - Tracking Keys

    private let lastBudgetedUpdateKey = "complication.lastBudgetedUpdate"
    private let lastBudgetedGlucoseKey = "complication.lastBudgetedGlucose"
    private let dailyUpdateCountKey = "complication.dailyUpdateCount"
    private let updateCountDateKey = "complication.updateCountDate"

    // MARK: - State

    private var lastBudgetedUpdateTime: Date? {
        get { UserDefaults.standard.object(forKey: lastBudgetedUpdateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastBudgetedUpdateKey) }
    }

    private var lastBudgetedGlucose: Double? {
        get { UserDefaults.standard.object(forKey: lastBudgetedGlucoseKey) as? Double }
        set { UserDefaults.standard.set(newValue, forKey: lastBudgetedGlucoseKey) }
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

    // MARK: - Private Methods

    private func shouldUseBudgetedUpdate(for data: ComplicationData) -> Bool {
        let now = Date()

        // Condition 1: Enough time has passed since last budgeted update
        let timeCondition: Bool
        if let lastUpdate = lastBudgetedUpdateTime {
            timeCondition = now.timeIntervalSince(lastUpdate) >= minimumUpdateInterval
        } else {
            // First update of the session
            timeCondition = true
        }

        // Condition 2: Significant glucose change
        let glucoseCondition: Bool
        if let currentGlucose = data.numericGlucose,
           let previousGlucose = lastBudgetedGlucose {
            let change = abs(currentGlucose - previousGlucose)
            // Use appropriate threshold based on value range
            // mmol/L values are typically < 30, mg/dL values are typically > 30
            let threshold = currentGlucose < 30 ? significantGlucoseChangeMmol : significantGlucoseChange
            glucoseCondition = change >= threshold
        } else {
            // No previous glucose to compare
            glucoseCondition = true
        }

        // Condition 3: Budget check - don't exceed daily limit
        let budgetAvailable = dailyUpdateCount < 50

        // Use budgeted update if: (time OR significant change) AND budget available
        return (timeCondition || glucoseCondition) && budgetAvailable
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
