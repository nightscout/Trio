import Foundation

/// Classifies where a bolus came from. User origins are tagged via `DoseEntry.bolusReference` and resolved on
/// return; `.smb` is derived from the dose. `rawValue` is the machine token; `displayName` the human label.
enum BolusOrigin: String, JSON {
    case smb
    case remote
    case watch
    case manual
    case shortcut

    /// Human-readable label recorded on the pump event note and uploaded to Nightscout (treatment `notes`).
    var displayName: String {
        switch self {
        case .smb: return "SMB"
        case .remote: return "Remote"
        case .watch: return "Watch"
        case .manual: return "Manual"
        case .shortcut: return "Shortcut"
        }
    }
}
