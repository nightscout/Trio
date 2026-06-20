import CGMBLEKit
import G7SensorKit
import LibreTransmitter
import LoopKit

/// Trio-side stand-in for LoopKit next-dev's `CGMManager.providesOwnGlucoseAlerts`.
/// Collapses to `manager?.providesOwnGlucoseAlerts ?? false` once the fork bumps.
enum CGMManagerAlertOwnership {
    static func providesOwnGlucoseAlerts(_ manager: CGMManager?) -> Bool {
        switch manager {
        case is G5CGMManager,
             is G6CGMManager,
             is G7CGMManager,
             is LibreTransmitterManagerV3:
            return true
        default:
            return false
        }
    }
}
