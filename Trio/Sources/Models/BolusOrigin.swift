import Foundation

/// Where a bolus request originated. Trio holds this meaning on its own side, keyed by an opaque reference
/// that is round-tripped through the pump (LoopKit `DoseEntry.bolusReference`), so a delivered dose can be
/// traced back to what asked for it — including across an app restart while delivery is in progress.
enum BolusOrigin: String, JSON {
    case remote
    case watch
    case manual
    case shortcut

    /// Human-readable label recorded on the pump event note and uploaded to Nightscout (treatment `notes`).
    var displayName: String {
        switch self {
        case .remote: return "Remote"
        case .watch: return "Watch"
        case .manual: return "Manual"
        case .shortcut: return "Shortcut"
        }
    }
}
