import CGMBLEKit
import G7SensorKit
import LoopKit

/// Trio-side stand-in for `CGMManager.providesOwnGlucoseAlerts`, which the
/// Dexcom kits don't set for eavesdropped sessions.
enum CGMManagerAlertOwnership {
    struct OwningApp {
        let name: String
        /// URL scheme registered by the companion app, if known. Schemes
        /// taken from the corresponding manager UI: `dexcomg6://` from
        /// CGMBLEKitUI's TransmitterSettingsViewController, `dexcomg7://`
        /// from G7SensorKitUI's G7SettingsView, `xdripswift://` from
        /// Trio's own CGMType.appURL. The manager protocol's `appURL`
        /// returns nil on our forks, so this table is the source of truth.
        let deepLink: URL?
    }

    static func providesOwnGlucoseAlerts(manager: CGMManager?, sourceType: CGMType) -> Bool {
        owningApp(manager: manager, sourceType: sourceType) != nil
    }

    static func owningApp(manager: CGMManager?, sourceType: CGMType) -> OwningApp? {
        // `.xdrip` runs without a CGMManager instance (App Group source),
        // so check the source type first.
        if sourceType == .xdrip {
            return OwningApp(name: "xDrip4iOS", deepLink: URL(string: "xdripswift://"))
        }
        switch manager {
        case is G5CGMManager:
            return OwningApp(name: "Dexcom G5", deepLink: nil)
        case is G6CGMManager:
            return OwningApp(name: "Dexcom G6 / One", deepLink: URL(string: "dexcomg6://"))
        case let manager as G7CGMManager:
            // Only an eavesdropped session has a Dexcom app behind it; direct
            // pairing requires that app to be gone, so nothing else alerts.
            guard manager.sessionMode == .eavesdropping else { return nil }
            return OwningApp(name: "Dexcom G7 / One+", deepLink: URL(string: "dexcomg7://"))
        default:
            return nil
        }
    }
}
