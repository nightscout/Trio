import CoreData
import Foundation

public extension ContactImageEntryStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactImageEntryStored> {
        NSFetchRequest<ContactImageEntryStored>(entityName: "ContactImageEntryStored")
    }

    @NSManaged var name: String
    @NSManaged var layout: String?
    @NSManaged var ring: String?
    @NSManaged var primary: String?
    @NSManaged var top: String?
    @NSManaged var bottom: String?
    @NSManaged var contactId: String?
    @NSManaged var hasHighContrast: Bool
    @NSManaged var ringWidth: Int16
    @NSManaged var ringGap: Int16
    @NSManaged var id: UUID?
    @NSManaged var fontSize: Int16
    @NSManaged var fontSizeSecondary: Int16
    @NSManaged var fontWidth: String?
    @NSManaged var fontWeight: String?
}
