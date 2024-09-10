import CoreData
import Foundation

public extension TempTargetsSlider {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempTargetsSlider> {
        NSFetchRequest<TempTargetsSlider>(entityName: "TempTargetsSlider")
    }

    @NSManaged var date: Date?
    @NSManaged var defaultHBT: Double
    @NSManaged var duration: NSDecimalNumber?
    @NSManaged var enabled: Bool
    @NSManaged var hbt: Double
    @NSManaged var id: String?
    @NSManaged var isPreset: Bool
}

extension TempTargetsSlider: Identifiable {}
