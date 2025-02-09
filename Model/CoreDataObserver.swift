import Combine
import CoreData
import Foundation

func changedObjectsOnManagedObjectContextDidSavePublisher() -> some Publisher<Set<NSManagedObjectID>, Never> {
    Foundation.NotificationCenter.default
        .publisher(for: NSNotification.Name.NSManagedObjectContextDidSave)
        .map { notification in
            guard let userInfo = notification.userInfo else { return Set<NSManagedObjectID>() }

            var objectIDs = Set<NSManagedObjectID>()

            if let inserted = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
                objectIDs.formUnion(inserted.map(\.objectID))
            }
            if let updated = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
                objectIDs.formUnion(updated.map(\.objectID))
            }
            if let deleted = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
                objectIDs.formUnion(deleted.map(\.objectID))
            }

            return objectIDs
        }
}

extension Publisher where Output == Set<NSManagedObjectID> {
    func filterByEntityName(_ name: String) -> some Publisher<Self.Output, Self.Failure> {
        filter { objectIDs in
            objectIDs.contains { objectID in
                objectID.entity.name == name
            }
        }
    }
}
