import Foundation

/// Controls which actions can be started from the Apple Watch app.
/// Shared between the iPhone app (enforcement) and the Watch app (UI).
enum WatchUsageMode: String, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case companion
    case adjustments
    case view

    var displayName: String {
        switch self {
        case .companion:
            return String(localized: "watch_usage_mode_companion", defaultValue: "Companion", comment: "Watch usage mode")
        case .adjustments:
            return String(localized: "watch_usage_mode_adjustments", defaultValue: "Adjustments", comment: "Watch usage mode")
        case .view:
            return String(localized: "watch_usage_mode_view", defaultValue: "View", comment: "Watch usage mode")
        }
    }

    /// Bolus, carb and meal entries
    var allowsTreatments: Bool {
        self == .companion
    }

    /// Overrides and temp targets
    var allowsAdjustments: Bool {
        self != .view
    }
}
