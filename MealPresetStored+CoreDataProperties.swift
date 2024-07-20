import Foundation
import CoreData


extension MealPresetStored {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MealPresetStored> {
        return NSFetchRequest<MealPresetStored>(entityName: "MealPresetStored")
    }

    @NSManaged public var carbs: NSDecimalNumber?
    @NSManaged public var dish: String?
    @NSManaged public var fat: NSDecimalNumber?
    @NSManaged public var protein: NSDecimalNumber?

}

extension MealPresetStored : Identifiable {

}
