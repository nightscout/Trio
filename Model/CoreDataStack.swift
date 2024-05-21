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

    // MARK: - Fetch Requests

    //
    // the first I define here is for background work...I decided to pass a parameter context to the function to execute it on the viewContext if necessary, but for updating the UI I've decided to rather create a second generic fetch function with a completion handler which results are returned on the main thread
    //
    // first fetch function
    // fetch on the thread of the backgroundContext
    func fetchEntities<T: NSManagedObject>(
        ofType type: T.Type,
        predicate: NSPredicate,
        key: String,
        ascending: Bool,
        fetchLimit: Int? = nil,
        batchSize: Int? = nil,
        propertiesToFetch: [String]? = nil,
        context: NSManagedObjectContext? = CoreDataStack.shared.backgroundContext,
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
        context?.performAndWait {
            do {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.succeeded) on Thread: \(Thread.current)"
                )
                result = try context?.fetch(request)
            } catch let error as NSError {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.failed) \(error) on Thread: \(Thread.current)"
                )
            }
        }

//        if result == nil {
//            debugPrint("Fetch result is nil in \(callingFunction) from \(callingClass) on thread \(Thread.current)")
//        } else {
//            debugPrint(
//                "Fetch result count: \(result?.count ?? 0) in \(callingFunction) from \(callingClass) on thread \(Thread.current)"
//            )
//        }

        return result ?? []
    }

    // second fetch function
    // fetch and update UI
    func fetchEntitiesAndUpdateUI<T: NSManagedObject>(
        ofType type: T.Type,
        predicate: NSPredicate,
        key: String,
        ascending: Bool,
        fetchLimit: Int? = nil,
        batchSize: Int? = nil,
        propertiesToFetch: [String]? = nil,
        callingFunction: String = #function,
        callingClass: String = #fileID,
        completion: @escaping ([T]) -> Void
    ) {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: String(describing: type))
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        request.predicate = predicate
        request.resultType = .managedObjectIDResultType
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        if let batchSize = batchSize {
            request.fetchBatchSize = batchSize
        }
        if let propertiesToFetch = propertiesToFetch {
            request.propertiesToFetch = propertiesToFetch
        }

        // perform fetch in the background
        //
        // the fetch returns a NSManagedObjectID which can be safely passed to the main queue because they are thread safe
        backgroundContext.perform {
            var result: [NSManagedObjectID]?

            do {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.succeeded) on thread \(Thread.current)"
                )
                result = try self.backgroundContext.fetch(request)
            } catch let error as NSError {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.failed) \(error) on thread \(Thread.current)"
                )
            }

            // change to the main queue to update UI
            DispatchQueue.main.async {
                if let result = result {
                    debugPrint(
                        "Returning fetch result to main thread in \(callingFunction) from \(callingClass) on thread \(Thread.current)"
                    )
                    // Convert NSManagedObjectIDs to objects in the main context
                    let mainContext = self.viewContext
                    let mainContextObjects = result.compactMap { mainContext.object(with: $0) as? T }
                    completion(mainContextObjects)
                } else {
                    debugPrint("Fetch result is nil in \(callingFunction) from \(callingClass) on thread \(Thread.current)")
                    completion([])
                }
            }
        }
    }

    // fetch and only return a NSManagedObjectID
    func fetchNSManagedObjectID<T: NSManagedObject>(
        ofType type: T.Type,
        predicate: NSPredicate,
        key: String,
        ascending: Bool,
        fetchLimit: Int? = nil,
        batchSize: Int? = nil,
        propertiesToFetch: [String]? = nil,
        callingFunction: String = #function,
        callingClass: String = #fileID,
        completion: @escaping ([NSManagedObjectID]) -> Void
    ) {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: String(describing: type))
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        request.predicate = predicate
        request.resultType = .managedObjectIDResultType
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        if let batchSize = batchSize {
            request.fetchBatchSize = batchSize
        }
        if let propertiesToFetch = propertiesToFetch {
            request.propertiesToFetch = propertiesToFetch
        }

        // Perform fetch in the background
        backgroundContext.perform {
            var result: [NSManagedObjectID]?

            do {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.succeeded) on thread \(Thread.current)"
                )
                result = try self.backgroundContext.fetch(request)
            } catch let error as NSError {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.failed) \(error) on thread \(Thread.current)"
                )
            }

            completion(result ?? [])
        }
    }

    // MARK: - Save

    //
    // takes a context as a parameter to be executed either on the main thread or on a background thread
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
