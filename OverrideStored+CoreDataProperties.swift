import Foundation
import CoreData


extension OverrideStored {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OverrideStored> {
        return NSFetchRequest<OverrideStored>(entityName: "OverrideStored")
    }

    @NSManaged public var advancedSettings: Bool
    @NSManaged public var cr: Bool
    @NSManaged public var date: Date?
    @NSManaged public var duration: NSDecimalNumber?
    @NSManaged public var enabled: Bool
    @NSManaged public var end: NSDecimalNumber?
    @NSManaged public var id: String?
    @NSManaged public var indefinite: Bool
    @NSManaged public var isf: Bool
    @NSManaged public var isfAndCr: Bool
    @NSManaged public var isPreset: Bool
    @NSManaged public var isUploadedToNS: Bool
    @NSManaged public var name: String?
    @NSManaged public var orderPosition: Int16
    @NSManaged public var percentage: Double
    @NSManaged public var smbIsAlwaysOff: Bool
    @NSManaged public var smbIsOff: Bool
    @NSManaged public var smbMinutes: NSDecimalNumber?
    @NSManaged public var start: NSDecimalNumber?
    @NSManaged public var target: NSDecimalNumber?
    @NSManaged public var uamMinutes: NSDecimalNumber?
    @NSManaged public var overrideRun: OverrideRunStored?

}

extension OverrideStored : Identifiable {

}
