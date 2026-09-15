import Foundation
import LoopKit

// LoopKit adapter for `EventType`.
//
// Kept out of `PumpHistoryEvent.swift` so that the model itself stays Foundation-only and can be
// compiled by the algorithm package (see `AlgorithmPackage/Package.swift`). Consumed by
// `TidepoolManager`.
extension EventType {
    func mapEventTypeToPumpEventType() -> PumpEventType? {
        switch self {
        case .prime:
            return PumpEventType.prime
        case .pumpResume:
            return PumpEventType.resume
        case .rewind:
            return PumpEventType.rewind
        case .pumpSuspend:
            return PumpEventType.suspend
        case .nsBatteryChange,
             .pumpBattery:
            return PumpEventType.replaceComponent(componentType: .pump)
        case .nsInsulinChange:
            return PumpEventType.replaceComponent(componentType: .reservoir)
        case .nsSiteChange:
            return PumpEventType.replaceComponent(componentType: .infusionSet)
        case .pumpAlarm:
            return PumpEventType.alarm
        default:
            return nil
        }
    }
}

extension InsulinType {
    /// Stable string identity for persistence; raw Int values must not be stored.
    var identifier: String {
        switch self {
        case .novolog: return "novolog"
        case .humalog: return "humalog"
        case .apidra: return "apidra"
        case .fiasp: return "fiasp"
        case .lyumjev: return "lyumjev"
        case .afrezza: return "afrezza"
        }
    }

    init?(identifier: String) {
        guard let match = InsulinType.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        self = match
    }
}
