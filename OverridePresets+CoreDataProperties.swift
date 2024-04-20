import CoreData
import Foundation

public extension OverridePresets {
    @nonobjc class func fetchRequest() -> NSFetchRequest<OverridePresets> {
        NSFetchRequest<OverridePresets>(entityName: "OverridePresets")
    }

    @NSManaged var advancedSettings: Bool
    @NSManaged var cr: Bool
    @NSManaged var date: Date?
    @NSManaged var duration: NSDecimalNumber?
    @NSManaged var end: NSDecimalNumber?
    @NSManaged var id: String?
    @NSManaged var indefinite: Bool
    @NSManaged var isf: Bool
    @NSManaged var isfAndCr: Bool
    @NSManaged var name: String?
    @NSManaged var percentage: Double
    @NSManaged var smbIsAlwaysOff: Bool
    @NSManaged var smbIsOff: Bool
    @NSManaged var smbMinutes: NSDecimalNumber?
    @NSManaged var start: NSDecimalNumber?
    @NSManaged var target: NSDecimalNumber?
    @NSManaged var uamMinutes: NSDecimalNumber?
}

extension OverridePresets: Identifiable {}
