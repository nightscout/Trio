import Foundation
import LoopKit

/// Glucose-driven alarm types Trio supports today. Order is priority order
/// (`urgentLow` highest), matching how `AlarmType.priority` works in
/// LoopFollow — when multiple alarms would fire on the same reading, the
/// higher-priority one wins and lower types of the same group are skipped.
enum GlucoseAlertType: String, Codable, CaseIterable, Identifiable {
    case urgentLow
    case low
    /// Glucose rate of change, not a level. `thresholdMgDL` stores the fall
    /// rate in mg/dL/min.
    case fallingFast
    case forecastedLow
    case high
    /// Mirror of `fallingFast`; `thresholdMgDL` stores the rise rate in mg/dL/min.
    case risingFast
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
        case .fallingFast,
             .high,
             .low,
             .risingFast,
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
        case .fallingFast: return String(localized: "Falling Fast")
        case .forecastedLow: return String(localized: "Low Glucose Soon")
        case .high: return String(localized: "High Glucose")
        case .risingFast: return String(localized: "Rising Fast")
        case .carbsRequired: return String(localized: "Carbs Required")
        }
    }

    var blurb: String {
        switch self {
        case .urgentLow: return String(localized: "Fires when glucose drops to or below an urgent low threshold.")
        case .low: return String(localized: "Fires when glucose drops to or below a low threshold.")
        case .fallingFast: return String(
                localized: "Fires when glucose is dropping at or faster than the selected rate. This is an early warning, not a prediction of a low."
            )
        case .forecastedLow: return String(localized: "Fires when glucose is forecasted to be low within the next 20 minutes.")
        case .high: return String(localized: "Fires when glucose rises to or above a high threshold.")
        case .risingFast: return String(
                localized: "Fires when glucose is rising at or faster than the selected rate."
            )
        case .carbsRequired: return String(localized: "Fires when oref recommends eating carbs to avoid a low.")
        }
    }

    /// Default threshold when adding a new alarm. Mg/dL for glucose types,
    /// mg/dL/min for `fallingFast` / `risingFast`, grams for `carbsRequired`.
    var defaultThresholdMgDL: Decimal {
        switch self {
        case .urgentLow: return 54
        case .low: return 72
        case .fallingFast: return 3
        case .forecastedLow: return 72
        case .high: return 270
        case .risingFast: return 3
        case .carbsRequired: return 10
        }
    }

    /// Default bundled sound filename. See `Trio/Resources/Sounds/`.
    /// Acoustic, Medium — the set the sound designer recommends as default
    /// after hallway testing. Falls back to the old generic tone only if the
    /// themed set is ever missing.
    var defaultSoundFilename: String {
        AlarmSoundCatalog.defaultFilename(for: .glucose(self)) ?? "alarm.caf"
    }

    /// Default for `GlucoseAlert.overridesSilenceAndDND` when adding a new
    /// alarm. Urgent-low defaults to override-on to match Loop's stance;
    /// others default off (time-sensitive, doesn't pierce DND / Focus).
    var defaultOverridesSilenceAndDND: Bool {
        switch self {
        case .urgentLow: return true
        case .carbsRequired,
             .fallingFast,
             .forecastedLow,
             .high,
             .low,
             .risingFast: return false
        }
    }

    /// Fires on the glucose rate of change rather than a level.
    var isRateDriven: Bool {
        self == .fallingFast || self == .risingFast
    }

    /// Rates offered for `fallingFast` / `risingFast`, in mg/dL/min (Dexcom's choices).
    static let rateThresholds: [Decimal] = [2, 3]

    /// A mg/dL/min rate in the user's units, e.g. "3 mg/dL/min" or "0.17 mmol/L/min".
    static func formattedRate(_ mgDLPerMinute: Decimal, units: GlucoseUnits) -> String {
        let value: String
        switch units {
        case .mgdL:
            value = Double(truncating: mgDLPerMinute as NSNumber).formatted(.number.precision(.fractionLength(0)))
        case .mmolL:
            value = Double(truncating: (mgDLPerMinute * GlucoseUnits.exchangeRate) as NSNumber)
                .formatted(.number.precision(.fractionLength(2)))
        }
        return String(
            format: String(localized: "%1$@ %2$@/min", comment: "Glucose rate, e.g. 3 mg/dL/min"),
            value,
            units.rawValue
        )
    }

    /// Whether the store seeds / backfills this type enabled. The rate
    /// alarms ship off, matching Dexcom's rate alerts.
    var isEnabledWhenSeeded: Bool {
        !isRateDriven
    }
}
