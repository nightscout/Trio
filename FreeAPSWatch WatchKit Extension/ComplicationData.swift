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

// MARK: - Complication Update Helper

enum ComplicationUpdateHelper {
    /// Reload all active complications
    static func reloadAllComplications() {
        let server = CLKComplicationServer.sharedInstance()
        guard let activeComplications = server.activeComplications else { return }

        for complication in activeComplications {
            server.reloadTimeline(for: complication)
        }
    }

    /// Extend timeline for all active complications
    static func extendAllComplications() {
        let server = CLKComplicationServer.sharedInstance()
        guard let activeComplications = server.activeComplications else { return }

        for complication in activeComplications {
            server.extendTimeline(for: complication)
        }
    }
}
