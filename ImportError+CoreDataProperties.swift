import Foundation
import CoreData


extension ImportError {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ImportError> {
        return NSFetchRequest<ImportError>(entityName: "ImportError")
    }

    @NSManaged public var date: Date?
    @NSManaged public var error: String?

}

extension ImportError : Identifiable {

}
