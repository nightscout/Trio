import Foundation

/// Keys used by `GlucoseSource.sourceInfo()` implementations to advertise
/// metadata about the active CGM (description, transmitter battery,
/// Nightscout ping). Consumed by status views + diagnostics.
enum GlucoseSourceKey: String {
    case transmitterBattery
    case nightscoutPing
    case description
}
