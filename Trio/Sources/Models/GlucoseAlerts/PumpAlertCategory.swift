import Foundation
import LoopKit

/// Fixed categories of pump / device alarms. Each maps to a
/// `DeviceAlertSeverity` tier — the user configures three tiers globally
/// (Critical / Time-Sensitive / Normal), not 13 categories individually.
enum PumpAlertCategory: String, Codable, CaseIterable, Identifiable {
    case occlusion
    case pumpFault
    case reservoirEmpty
    case reservoirLow
    case batteryEmpty
    case batteryLow
    case bolusFailed
    case manualTempBasalActive
    case podExpirationReminder
    case podExpired
    case podShutdownImminent
    case suspendTimeExpired
    case glucoseDataStale

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .occlusion: return String(localized: "Occlusion")
        case .pumpFault: return String(localized: "Pump Fault")
        case .reservoirEmpty: return String(localized: "Reservoir Empty")
        case .reservoirLow: return String(localized: "Reservoir Low")
        case .batteryEmpty: return String(localized: "Battery Empty")
        case .batteryLow: return String(localized: "Battery Low")
        case .bolusFailed: return String(localized: "Bolus Failed")
        case .manualTempBasalActive: return String(localized: "Manual Temp Basal Active")
        case .podExpirationReminder: return String(localized: "Pod Expiration Reminder")
        case .podExpired: return String(localized: "Pod Expired")
        case .podShutdownImminent: return String(localized: "Pod Shutdown Imminent")
        case .suspendTimeExpired: return String(localized: "Suspend Time Expired")
        case .glucoseDataStale: return String(localized: "Glucose Data Stale")
        }
    }

    /// Maps this category to one of the three tier configs the user edits.
    var defaultSeverity: DeviceAlertSeverity {
        switch self {
        case .batteryEmpty,
             .occlusion,
             .pumpFault,
             .reservoirEmpty:
            return .critical
        case .batteryLow,
             .bolusFailed,
             .glucoseDataStale,
             .manualTempBasalActive,
             .podExpired,
             .podShutdownImminent,
             .reservoirLow,
             .suspendTimeExpired:
            return .timeSensitive
        case .podExpirationReminder:
            return .normal
        }
    }

    init?(trioCategory: TrioAlertCategory) {
        switch trioCategory {
        case .occlusion: self = .occlusion
        case .pumpFault: self = .pumpFault
        case .reservoirEmpty: self = .reservoirEmpty
        case .reservoirLow: self = .reservoirLow
        case .batteryEmpty: self = .batteryEmpty
        case .batteryLow: self = .batteryLow
        case .bolusFailed: self = .bolusFailed
        case .manualTempBasalActive: self = .manualTempBasalActive
        case .podExpirationReminder: self = .podExpirationReminder
        case .podExpired: self = .podExpired
        case .podShutdownImminent: self = .podShutdownImminent
        case .suspendTimeExpired: self = .suspendTimeExpired
        case .glucoseDataStale: self = .glucoseDataStale
        default: return nil
        }
    }
}
