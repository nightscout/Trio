import Foundation

struct PumpStatus: JSON, Equatable {
    let status: StatusType
    let bolusing: Bool
    let suspended: Bool
    var timestamp: Date?
}

extension PumpStatus {
    /// Also suspended while the pump manager reports delivery active since before the last pump
    /// suspend that no resume, temp basal or pump bolus followed. Omnipod reports delivery as active
    /// since `.distantPast` while no pod is active.
    func includingSuspend(deliveryActiveSince: Date, lastPumpEvent: (type: String, date: Date)?) -> PumpStatus {
        guard !suspended, let lastPumpEvent,
              lastPumpEvent.type == PumpEventStored.EventType.pumpSuspend.rawValue,
              deliveryActiveSince < lastPumpEvent.date
        else { return self }
        return PumpStatus(status: .suspended, bolusing: bolusing, suspended: true, timestamp: timestamp)
    }
}

enum StatusType: String, JSON {
    case normal
    case suspended
    case bolusing
}
