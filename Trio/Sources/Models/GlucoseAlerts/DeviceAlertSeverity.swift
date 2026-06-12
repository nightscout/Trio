import Foundation
import LoopKit

/// Coarse-grained tier the user configures for device alarms. Wraps
/// `Alert.InterruptionLevel` plus its visible behavior:
/// - `.critical` overrides Silence & Focus Mode (uses the critical-audio
///   fallback for builds without the Critical Alerts entitlement)
/// - `.timeSensitive` pierces normal banner suppression but obeys DND/silent
/// - `.normal` fires only when the device isn't silenced — informational
enum DeviceAlertSeverity: String, Codable, CaseIterable, Identifiable {
    case critical
    case timeSensitive
    case normal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .critical: return String(localized: "Critical")
        case .timeSensitive: return String(localized: "Time-Sensitive")
        case .normal: return String(localized: "Normal")
        }
    }

    var blurb: String {
        switch self {
        case .critical:
            return String(localized: "Overrides Silence & Focus Mode. Always audible. For hazardous failures.")
        case .timeSensitive:
            return String(localized: "Pierces banner suppression but obeys Silence & Focus Mode.")
        case .normal:
            return String(localized: "Default notification banner. Suppressed by Silence and DND.")
        }
    }

    var defaultSoundFilename: String {
        switch self {
        case .critical: return "alarm.caf"
        case .timeSensitive: return "chime.caf"
        case .normal: return "bloop.caf"
        }
    }

    /// Default for the per-tier override toggle when seeded. Tier names are
    /// labels now — the actual `Alert.InterruptionLevel` is derived from the
    /// override flag at fire time (true → `.critical`, false → `.timeSensitive`).
    var defaultOverridesSilenceAndDND: Bool {
        switch self {
        case .critical: return true
        case .normal,
             .timeSensitive: return false
        }
    }
}
