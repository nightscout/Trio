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

    /// Without a pump manager nothing is bolusing, and the timestamp is when the stored state began.
    var pumpStatus: PumpStatus {
        PumpStatus(deliveryState: deliveryState, bolusing: false, timestamp: date)
    }
}
