import CoreData
import Foundation

extension PumpStatusStored {
    /// Basal delivery as the pump manager reports it. Temp basals and their transitions count as active.
    enum DeliveryState: String {
        case active
        /// Delivery active since `.distantPast`, which Omnipod reports while no pod is active.
        case inactive
        case suspending
        case suspended
        case resuming
        /// No basal delivery state, or no pump.
        case unknown
    }

    static func fetchLast() -> NSFetchRequest<PumpStatusStored> {
        let request = PumpStatusStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PumpStatusStored.date, ascending: false)]
        request.fetchLimit = 1
        return request
    }

    var deliveryState: DeliveryState {
        basalDeliveryState.flatMap(DeliveryState.init(rawValue:)) ?? .unknown
    }

    /// Suspended for any state without delivery. Without a pump manager nothing is bolusing, and the
    /// timestamp is the upload time, as for a status read from the pump manager.
    var pumpStatus: PumpStatus {
        let suspended = [.suspended, .inactive, .unknown].contains(deliveryState)
        return PumpStatus(status: suspended ? .suspended : .normal, bolusing: false, suspended: suspended, timestamp: Date())
    }
}
