import CGMBLEKit
import G7SensorKit
import LibreTransmitter
import LoopKit

/// Trio-side stand-in for LoopKit next-dev's `CGMManager.providesOwnGlucoseAlerts`.
/// Collapses to `manager?.providesOwnGlucoseAlerts ?? false` once the fork bumps.
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
        case is G7CGMManager:
            return OwningApp(name: "Dexcom G7 / One+", deepLink: URL(string: "dexcomg7://"))
        case is LibreTransmitterManagerV3:
            return OwningApp(name: "FreeStyle Libre", deepLink: nil)
        default:
            return nil
        }
    }
}
