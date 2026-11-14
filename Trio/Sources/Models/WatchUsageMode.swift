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
            return String(localized: "Companion")
        case .adjustments:
            return String(localized: "Adjustments")
        case .view:
            return String(localized: "View")
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

    /// Whether this mode allows the action requested by a message from the Watch.
    /// Counts every message the iPhone's handlers would act on (and malformed bolus messages) as a request.
    /// Messages that only request data (state updates, bolus recommendations without a date) or snooze alerts
    /// are always allowed.
    func allows(watchMessage message: [String: Any]) -> Bool {
        let isTreatment = message[WatchMessageKeys.bolus] as? Double != nil ||
            (message[WatchMessageKeys.carbs] as? Int != nil && message[WatchMessageKeys.date] as? TimeInterval != nil)
        let isAdjustment = message[WatchMessageKeys.cancelOverride] as? Bool == true ||
            message[WatchMessageKeys.activateOverride] as? String != nil ||
            message[WatchMessageKeys.activateTempTarget] as? String != nil ||
            message[WatchMessageKeys.cancelTempTarget] as? Bool == true
        return (!isTreatment || allowsTreatments) && (!isAdjustment || allowsAdjustments)
    }
}
