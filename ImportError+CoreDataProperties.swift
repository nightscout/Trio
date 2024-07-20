import CoreData
import Foundation

public extension ImportError {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ImportError> {
        NSFetchRequest<ImportError>(entityName: "ImportError")
    }

    @NSManaged var date: Date?
    @NSManaged var error: String?
}

extension ImportError: Identifiable {}
