import CoreData
import Foundation

public extension MealsStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MealsStored> {
        NSFetchRequest<MealsStored>(entityName: "MealsStored")
    }

    @NSManaged var carbs: Double
    @NSManaged var date: Date?
    @NSManaged var fat: Double
    @NSManaged var id: UUID?
    @NSManaged var isFPU: Bool
    @NSManaged var note: String?
    @NSManaged var protein: Double
}

extension MealsStored: Identifiable {}
