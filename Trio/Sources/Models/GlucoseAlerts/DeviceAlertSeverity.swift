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

    init?(level: Alert.InterruptionLevel) {
        switch level {
        case .critical: self = .critical
        case .timeSensitive: self = .timeSensitive
        case .active: self = .normal
        }
    }

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
            return String(localized: "Overrides Silence & Focus Mode. For situations requiring immediate attention.")
        case .timeSensitive:
            return String(localized: "Pierces banner suppression but obeys Silence & Focus Mode by default.")
        case .normal:
            return String(localized: "Default notification banner. Suppressed by Silence & Focus Mode by default.")
        }
    }

    var hintText: String {
        switch self {
        case .critical:
            return String(
                localized: "For situations that require prompt attention. These break through Silent Mode, Do Not Disturb, and any Focus you have enabled. Examples: a pump fault, an occlusion, or Trio not looping for too long. Heads up: if your build of Trio has Apple's Critical Alerts entitlement, iOS plays its own critical alert sound and the sound you picked for this alert category is ignored."
            )
        case .timeSensitive:
            return String(
                localized: "For things you should know about soon, but not 'act right now'. These can break through banner suppression on the lock screen, but they still obey Silent Mode and Focus by default. Examples: reservoir running low, pod or patch expiring soon, or glucose data going stale."
            )
        case .normal:
            return String(
                localized: "For everyday heads-up notifications. These behave like a standard banner — they stay quiet when your phone is silenced or a Focus is on. Examples: an algorithm error, a sensor expiration reminder, or a time-zone change being detected."
            )
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
