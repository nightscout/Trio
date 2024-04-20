import CoreData
import Foundation

public extension Presets {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Presets> {
        NSFetchRequest<Presets>(entityName: "Presets")
    }

    @NSManaged var carbs: NSDecimalNumber?
    @NSManaged var dish: String?
    @NSManaged var fat: NSDecimalNumber?
    @NSManaged var protein: NSDecimalNumber?
}

extension Presets: Identifiable {}
