import Foundation
import LoopKit

/// Glucose-driven alarm types Trio supports today. Order is priority order
/// (`urgentLow` highest), matching how `AlarmType.priority` works in
/// LoopFollow — when multiple alarms would fire on the same reading, the
/// higher-priority one wins and lower types of the same group are skipped.
enum GlucoseAlertType: String, Codable, CaseIterable, Identifiable {
    case urgentLow
    case low
    case forecastedLow
    case high
    /// Driven by `Determination.carbsReq`, not by a glucose reading. Stored
    /// alongside the other glucose alarms so the user has one place to
    /// configure schedule/sound/snooze for everything fired by Trio.
    case carbsRequired

    var id: String { rawValue }

    var priority: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// `true` when the alarm fires off a CGM glucose reading. `false` for
    /// `forecastedLow` (driven by the determination forecast) and
    /// `carbsRequired` (driven by the determination's `carbsReq` field).
    var isReadingDriven: Bool {
        switch self {
        case .high,
             .low,
             .urgentLow:
            return true
        case .carbsRequired,
             .forecastedLow:
            return false
        }
    }

    /// Parses a glucose-alarm slug emitted by `GlucoseAlertCoordinator`
    /// (`glucose.<type>.<uuid>`). Returns nil for non-glucose alert
    /// identifiers — used by `BaseTrioAlertManager.requestSnooze` to decide
    /// between per-type and global mute routing.
    init?(slug: String) {
        let parts = slug.split(separator: ".")
        guard parts.count >= 2, parts[0] == "glucose" else { return nil }
        guard let parsed = GlucoseAlertType(rawValue: String(parts[1])) else { return nil }
        self = parsed
    }

    var displayName: String {
        switch self {
        case .urgentLow: return String(localized: "Urgent Low Glucose")
        case .low: return String(localized: "Low Glucose")
        case .forecastedLow: return String(localized: "Low Glucose Soon")
        case .high: return String(localized: "High Glucose")
        case .carbsRequired: return String(localized: "Carbs Required")
        }
    }

    var blurb: String {
        switch self {
        case .urgentLow: return String(localized: "Fires when glucose drops to or below an urgent low threshold.")
        case .low: return String(localized: "Fires when glucose drops to or below a low threshold.")
        case .forecastedLow: return String(localized: "Fires when glucose is forecasted to be low within the next 20 minutes.")
        case .high: return String(localized: "Fires when glucose rises to or above a high threshold.")
        case .carbsRequired: return String(localized: "Fires when oref recommends eating carbs to avoid a low.")
        }
    }

    /// Default threshold when adding a new alarm. Mg/dL for glucose types,
    /// grams for `carbsRequired`.
    var defaultThresholdMgDL: Decimal {
        switch self {
        case .urgentLow: return 54
        case .low: return 72
        case .forecastedLow: return 72
        case .high: return 270
        case .carbsRequired: return 10
        }
    }

    /// Default bundled sound filename. See `Trio/Resources/Sounds/`.
    var defaultSoundFilename: String {
        switch self {
        case .urgentLow: return "urgent_low.caf"
        case .low: return "trill.caf"
        case .forecastedLow: return "bloom.caf"
        case .high: return "chime.caf"
        case .carbsRequired: return "bloop.caf"
        }
    }

    /// Default for `GlucoseAlert.overridesSilenceAndDND` when adding a new
    /// alarm. Urgent-low defaults to override-on to match Loop's stance;
    /// others default off (time-sensitive, doesn't pierce DND / Focus).
    var defaultOverridesSilenceAndDND: Bool {
        switch self {
        case .urgentLow: return true
        case .carbsRequired,
             .forecastedLow,
             .high,
             .low: return false
        }
    }
}
