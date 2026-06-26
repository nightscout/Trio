import Foundation
import LoopKit

/// Plugin-side declaration of every alert a device manager may issue.
/// Mirrors LoopKit's `AlertSoundVendor` pattern (static, boot-time, no
/// side effects). Trio uses the union catalog to drive per-alert severity,
/// the Settings UI, and per-alert mute. When upstream LoopKit adopts this,
/// Trio's bridge extensions move into the plugin repos verbatim.
protocol AlertCatalogVendor {
    var alertCatalog: [Alert.CatalogEntry] { get }
}

extension Alert {
    /// Cross-plugin canonical key for the Settings UI. Multiple per-plugin
    /// entries with the same concept collapse to a single row.
    enum CatalogConcept: Hashable {
        case occlusion
        case reservoirLow
        case reservoirEmpty
        case pumpBatteryLow
        case pumpBatteryEmpty
        case rileyLinkBatteryLow
        case hardwareFault
        case insulinLimitWarning
        case insulinLimitReached
        case suspendInProgressReminder
        case insulinResumeReminder
        case deviceExpirationReminder
        case deviceExpired
        case deviceShutdownImminent
        case setupIncomplete
        case timeChange
        case pairingFailed
        case userBloodGlucoseReminder
        case basalProfileMismatch
        /// Plugin-unique alarm that doesn't merge with anything else.
        case unspecified

        var displayTitle: String {
            switch self {
            case .occlusion: return String(localized: "Occlusion")
            case .reservoirLow: return String(localized: "Reservoir Low")
            case .reservoirEmpty: return String(localized: "Reservoir Empty")
            case .pumpBatteryLow: return String(localized: "Pump Battery Low")
            case .pumpBatteryEmpty: return String(localized: "Pump Battery Empty")
            case .rileyLinkBatteryLow: return String(localized: "RileyLink Battery Low")
            case .hardwareFault: return String(localized: "Pump Fault")
            case .insulinLimitWarning: return String(localized: "Insulin Limit Warning")
            case .insulinLimitReached: return String(localized: "Insulin Limit Reached")
            case .suspendInProgressReminder: return String(localized: "Suspend In Progress")
            case .insulinResumeReminder: return String(localized: "Insulin Resume Reminder")
            case .deviceExpirationReminder: return String(localized: "Device Expiration Reminder")
            case .deviceExpired: return String(localized: "Device Expired")
            case .deviceShutdownImminent: return String(localized: "Device Shutdown Imminent")
            case .setupIncomplete: return String(localized: "Setup Incomplete")
            case .timeChange: return String(localized: "Time Change Detected")
            case .pairingFailed: return String(localized: "Pairing Failed")
            case .userBloodGlucoseReminder: return String(localized: "Blood Glucose Reminder")
            case .basalProfileMismatch: return String(localized: "Basal Profile Mismatch")
            case .unspecified: return ""
            }
        }
    }

    struct CatalogEntry: Identifiable, Equatable {
        let identifier: Alert.Identifier
        let interruptionLevel: Alert.InterruptionLevel
        /// Plugin's authentic title — surfaces in logs / debug paths.
        let title: String
        /// Soft grouping ("Delivery", "Reservoir", "Hardware", ...).
        let category: String
        /// UI dedupe key — entries sharing a concept collapse to one row.
        let concept: CatalogConcept

        var id: String { identifier.value }

        init(
            identifier: Alert.Identifier,
            interruptionLevel: Alert.InterruptionLevel,
            title: String,
            category: String,
            concept: CatalogConcept
        ) {
            self.identifier = identifier
            self.interruptionLevel = interruptionLevel
            self.title = title
            self.category = category
            self.concept = concept
        }

        init(
            managerIdentifier: String,
            alertIdentifier: Alert.AlertIdentifier,
            interruptionLevel: Alert.InterruptionLevel,
            title: String,
            category: String,
            concept: CatalogConcept
        ) {
            self.init(
                identifier: Alert.Identifier(
                    managerIdentifier: managerIdentifier,
                    alertIdentifier: alertIdentifier
                ),
                interruptionLevel: interruptionLevel,
                title: title,
                category: category,
                concept: concept
            )
        }
    }
}
