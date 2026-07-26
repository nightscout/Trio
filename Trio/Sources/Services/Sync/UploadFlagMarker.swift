import CoreData
import Foundation

/// Marks Core Data rows as uploaded to a backend by flipping that backend's boolean
/// flag (e.g. `\.isUploadedToNS`). One shared implementation of the
/// fetch-by-id / set-flag / save step every uploader performs after a successful upload.
enum UploadFlagMarker {
    /// Sets `flag` to true on all `Entity` rows whose `id` attribute is contained in
    /// `ids`, on a fresh background task context.
    ///
    /// - Parameters:
    ///   - ids: Ids of the uploaded payload items, matched against the entity's `id`
    ///     attribute. Passed as `NSArray` so callers keep their existing
    ///     `payload.map(\.id) as NSArray` bridging, whatever the element type.
    ///   - flag: The backend's "uploaded" flag, e.g. `\.isUploadedToNS`.
    ///   - contextName: Name for the task context; also used in failure logs.
    static func markUploaded<Entity: NSManagedObject>(
        _: Entity.Type,
        ids: NSArray,
        flag: ReferenceWritableKeyPath<Entity, Bool>,
        contextName: String
    ) async {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = contextName
        await context.perform {
            let fetchRequest = NSFetchRequest<Entity>(entityName: String(describing: Entity.self))
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try context.fetch(fetchRequest)
                for result in results {
                    result[keyPath: flag] = true
                }

                guard context.hasChanges else { return }
                try context.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(contextName) failed to update upload flag: \(error.userInfo)"
                )
            }
        }
    }
}
