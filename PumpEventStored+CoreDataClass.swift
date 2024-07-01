import CoreData
import Foundation

@objc(PumpEventStored) public class PumpEventStored: NSManagedObject {
    let errorDomain = "PumpEventStoredErrorDomain"

    enum PumpEventErrorType: Int {
        case duplicate = 1001
    }
}
