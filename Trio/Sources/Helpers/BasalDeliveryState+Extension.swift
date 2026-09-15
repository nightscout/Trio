import LoopKit

extension PumpManagerStatus.BasalDeliveryState {
    var isManualTempBasal: Bool {
        guard case let .tempBasal(dose) = self else { return false }
        return !(dose.automatic ?? true)
    }
}
