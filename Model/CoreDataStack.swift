import CoreData
import Foundation

class CoreDataStack: ObservableObject {
    init() {}

    static let shared = CoreDataStack()
    static let identifier = "CoreDataStack"

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Core_Data")

        container.loadPersistentStores(completionHandler: { _, error in
            guard let error = error as NSError? else { return }
            fatalError("Unresolved error: \(error), \(error.userInfo)")
        })

        return container
    }()

    // ensure thread safety by creating a NSManagedObjectContext for the main thread and for a background thread
    lazy var backgroundContext: NSManagedObjectContext = {
        let newbackgroundContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
        newbackgroundContext.automaticallyMergesChangesFromParent = true
        newbackgroundContext
            .mergePolicy =
            NSMergeByPropertyStoreTrumpMergePolicy // if two objects with the same unique constraint are found, overwrite with the object in the external storage
        return newbackgroundContext
    }()

    lazy var viewContext: NSManagedObjectContext = {
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
        viewContext.automaticallyMergesChangesFromParent = true
        return viewContext
    }()

    // fetch on the thread of the backgroundContext
    func fetchEntities<T: NSManagedObject>(
        ofType type: T.Type,
        predicate: NSPredicate,
        key: String,
        ascending: Bool,
        fetchLimit: Int? = nil,
        batchSize: Int? = nil,
        propertiesToFetch: [String]? = nil,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        request.predicate = predicate
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        if let batchSize = batchSize {
            request.fetchBatchSize = batchSize
        }
        if let propertiesTofetch = propertiesToFetch {
            request.propertiesToFetch = propertiesTofetch
            request.resultType = .managedObjectResultType
        } else {
            request.resultType = .managedObjectResultType
        }

        var result: [T]?

        /// we need to ensure that the fetch immediately returns a value as long as the whole app does not use the async await pattern, otherwise we could perform this asynchronously with backgroundContext.perform and not block the thread
        backgroundContext.performAndWait {
            do {
                debugPrint("Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.succeeded)")
                result = try self.backgroundContext.fetch(request)
            } catch let error as NSError {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.failed) \(error)"
                )
            }
        }
        return result ?? []
    }

    // save on the thread of the backgroundContext
    func saveContext(useViewContext: Bool = false, callingFunction: String = #function, callingClass: String = #fileID) throws {
        let contextToUse = useViewContext ? viewContext : backgroundContext

        try contextToUse.performAndWait {
            if contextToUse.hasChanges {
                do {
                    try self.backgroundContext.save()
                    debugPrint(
                        "Saving to Core Data successful in \(callingFunction) in \(callingClass): \(DebuggingIdentifiers.succeeded)"
                    )
                } catch let error as NSError {
                    debugPrint(
                        "Saving to Core Data failed in \(callingFunction) in \(callingClass): \(DebuggingIdentifiers.failed) with error \(error), \(error.userInfo)"
                    )
                    throw error
                }
            }
        }
    }
}
