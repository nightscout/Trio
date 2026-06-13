import Foundation
import LoopKit

/// Fixed categories of pump / device alarms. Each maps to a
/// `DeviceAlertSeverity` tier — the user configures three tiers globally
/// (Critical / Time-Sensitive / Normal), not 13+ categories individually.
enum PumpAlertCategory: String, Codable, CaseIterable, Identifiable {
    case occlusion
    case hardwareFault
    case reservoirEmpty
    case reservoirLow
    case batteryEmpty
    case batteryLow
    case bolusFailed
    case deliveryUncertain
    case manualTempBasalActive
    case notLooping
    case sensorFailure
    case deviceExpirationReminder
    case deviceExpired
    case podShutdownImminent
    case suspendTimeExpired
    case glucoseDataStale
    case algorithmError

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .occlusion: return String(localized: "Occlusion")
        case .hardwareFault: return String(localized: "Hardware Fault")
        case .reservoirEmpty: return String(localized: "Reservoir Empty")
        case .reservoirLow: return String(localized: "Reservoir Low")
        case .batteryEmpty: return String(localized: "Battery Empty")
        case .batteryLow: return String(localized: "Battery Low")
        case .bolusFailed: return String(localized: "Bolus Failed")
        case .deliveryUncertain: return String(localized: "Delivery Uncertain")
        case .manualTempBasalActive: return String(localized: "Manual Temp Basal Active")
        case .notLooping: return String(localized: "Loop Not Running")
        case .sensorFailure: return String(localized: "Sensor Failure")
        case .deviceExpirationReminder: return String(localized: "Device Expiration Reminder")
        case .deviceExpired: return String(localized: "Device Expired")
        case .podShutdownImminent: return String(localized: "Shutdown Imminent")
        case .suspendTimeExpired: return String(localized: "Suspend Time Expired")
        case .glucoseDataStale: return String(localized: "Glucose Data Stale")
        case .algorithmError: return String(localized: "Algorithm Error")
        }
    }

    /// Maps this category to one of the three tier configs the user edits.
    var defaultSeverity: DeviceAlertSeverity {
        switch self {
        case .batteryEmpty,
             .deliveryUncertain,
             .hardwareFault,
             .notLooping,
             .occlusion,
             .reservoirEmpty,
             .sensorFailure:
            return .critical
        case .batteryLow,
             .bolusFailed,
             .deviceExpired,
             .glucoseDataStale,
             .manualTempBasalActive,
             .podShutdownImminent,
             .reservoirLow,
             .suspendTimeExpired:
            return .timeSensitive
        case .algorithmError,
             .deviceExpirationReminder:
            return .normal
        }
    }

    init?(trioCategory: TrioAlertCategory) {
        switch trioCategory {
        case .occlusion: self = .occlusion
        case .hardwareFault: self = .hardwareFault
        case .reservoirEmpty: self = .reservoirEmpty
        case .reservoirLow: self = .reservoirLow
        case .batteryEmpty: self = .batteryEmpty
        case .batteryLow: self = .batteryLow
        case .bolusFailed: self = .bolusFailed
        case .deliveryUncertain: self = .deliveryUncertain
        case .manualTempBasalActive: self = .manualTempBasalActive
        case .notLooping: self = .notLooping
        case .sensorFailure: self = .sensorFailure
        case .deviceExpirationReminder: self = .deviceExpirationReminder
        case .deviceExpired: self = .deviceExpired
        case .podShutdownImminent: self = .podShutdownImminent
        case .suspendTimeExpired: self = .suspendTimeExpired
        case .glucoseDataStale: self = .glucoseDataStale
        case .algorithmError: self = .algorithmError
        default: return nil
        }
    }
}
