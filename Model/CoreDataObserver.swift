import Combine
import CoreData
import Foundation

func changedObjectsOnManagedObjectContextDidSavePublisher() -> some Publisher<Set<NSManagedObject>, Never> {
    Foundation.NotificationCenter.default
        .publisher(for: NSNotification.Name.NSManagedObjectContextDidSave)
        .map { notification in
            guard let userInfo = notification.userInfo else { return Set<NSManagedObject>() }

            var objects = Set((userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? [])
            objects.formUnion((userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? [])
            objects.formUnion((userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? [])

            return objects
        }
}

extension Publisher where Output == Set<NSManagedObject> {
    func filterByEntityName(_ name: String) -> some Publisher<Self.Output, Self.Failure> {
        filter { objects in
            objects.contains(where: { $0.entity.name == name })
        }
    }
}
