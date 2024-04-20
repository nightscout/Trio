import CoreData
import Foundation

public extension Protein {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Protein> {
        NSFetchRequest<Protein>(entityName: "Protein")
    }

    @NSManaged var date: Date?
    @NSManaged var enteredBy: String?
    @NSManaged var protein: NSDecimalNumber?
}

extension Protein: Identifiable {}
