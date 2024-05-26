import CoreData
import Foundation
import OSLog

class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    static let identifier = "CoreDataStack"

    private var notificationToken: NSObjectProtocol?
    private let inMemory: Bool

    private init(inMemory: Bool = false) {
        self.inMemory = inMemory

        // Observe Core Data remote change notifications on the queue where the changes were made
        notificationToken = Foundation.NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { _ in
            debugPrint("Received a persistent store remote change notification")
            Task {
                await self.fetchPersistentHistory()
            }
        }
    }

    deinit {
        if let observer = notificationToken {
            Foundation.NotificationCenter.default.removeObserver(observer)
        }
    }

    /// A persistent history token used for fetching transactions from the store
    private var lastToken: NSPersistentHistoryToken?

    /// A persistent container to set up the Core Data Stack
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Core_Data")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed \(DebuggingIdentifiers.failed) to retrieve a persistent store description")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        // Enable persistent store remote change notifications
        /// - Tag: persistentStoreRemoteChange
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Enable persistent history tracking
        /// - Tag: persistentHistoryTracking
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved Error \(DebuggingIdentifiers.failed) \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = false
        container.viewContext.name = "viewContext"
        /// - Tag: viewContextmergePolicy
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true
        return container
    }()

    /// Creates and configures a private queue context
    private func newTaskContext() -> NSManagedObjectContext {
        // Create a private queue context
        /// - Tag: newBackgroundContext
        let taskContext = persistentContainer.newBackgroundContext()

        /// ensure that the background contexts stay in sync with the main context
        taskContext.automaticallyMergesChangesFromParent = true
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        taskContext.undoManager = nil
        return taskContext
    }

    func fetchPersistentHistory() async {
        do {
            try await fetchPersistentHistoryTransactionsAndChanges()
        } catch {
            debugPrint("\(error.localizedDescription)")
        }
    }

    private func fetchPersistentHistoryTransactionsAndChanges() async throws {
        let taskContext = newTaskContext()
        taskContext.name = "persistentHistoryContext"
        debugPrint("Start fetching persistent history changes from the store ... \(DebuggingIdentifiers.inProgress)")

        try await taskContext.perform {
            // Execute the persistent history change since the last transaction
            /// - Tag: fetchHistory
            let changeRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: self.lastToken)
            let historyResult = try taskContext.execute(changeRequest) as? NSPersistentHistoryResult
            if let history = historyResult?.result as? [NSPersistentHistoryTransaction], !history.isEmpty {
                self.mergePersistentHistoryChanges(from: history)
                return
            }
        }
    }

    private func mergePersistentHistoryChanges(from history: [NSPersistentHistoryTransaction]) {
        debugPrint("Received \(history.count) persistent history transactions")
        // Update view context with objectIDs from history change request
        /// - Tag: mergeChanges
        let viewContext = persistentContainer.viewContext
        viewContext.perform {
            for transaction in history {
                viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
                self.lastToken = transaction.token
            }
        }
    }

    // MARK: - Fetch Requests

    // Fetch in background thread
    /// - Tag: backgroundFetch
    func fetchEntities<T: NSManagedObject>(
        ofType type: T.Type,
        onContext context: NSManagedObjectContext,
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

        context.name = "fetchContext"
        context.transactionAuthor = "fetchEntities"

        var result: [T]?

        /// we need to ensure that the fetch immediately returns a value as long as the whole app does not use the async await pattern, otherwise we could perform this asynchronously with backgroundContext.perform and not block the thread
        context.performAndWait {
            do {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.succeeded) on Thread: \(Thread.current)"
                )
                result = try context.fetch(request)
            } catch let error as NSError {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.failed) \(error) on Thread: \(Thread.current)"
                )
            }
        }

        return result ?? []
    }

    // TODO: -refactor this, currently only the BolusStateModel uses this because we need to fetch in the background, then do calculations and after this update the UI
    
    // Fetch and update UI
    /// - Tag: uiFetch
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

        let taskContext = newTaskContext()
        taskContext.name = "fetchContext"
        taskContext.transactionAuthor = "fetchEntities"

        // perform fetch in the background
        //
        // the fetch returns a NSManagedObjectID which can be safely passed to the main queue because they are thread safe
        taskContext.perform {
            var result: [NSManagedObjectID]?

            do {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.succeeded) on thread \(Thread.current)"
                )
                result = try taskContext.fetch(request)
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
                    let mainContext = CoreDataStack.shared.persistentContainer.viewContext
                    let mainContextObjects = result.compactMap { mainContext.object(with: $0) as? T }
                    completion(mainContextObjects)
                } else {
                    debugPrint("Fetch result is nil in \(callingFunction) from \(callingClass) on thread \(Thread.current)")
                    completion([])
                }
            }
        }
    }

    // Fetch the NSManagedObjectIDs
    // Useful if we need to pass the NSManagedObject to another thread as the objectID is thread safe
    /// - Tag: fetchIDs
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

        let taskContext = newTaskContext()
        taskContext.name = "fetchContext"
        taskContext.transactionAuthor = "fetchEntities"

        // Perform fetch in the background
        taskContext.perform {
            var result: [NSManagedObjectID]?

            do {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.succeeded) on thread \(Thread.current)"
                )
                result = try taskContext.fetch(request)
            } catch let error as NSError {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.failed) \(error) on thread \(Thread.current)"
                )
            }

            completion(result ?? [])
        }
    }

    // MARK: - Delete

    /// Synchronously delete entries with specified object IDs
    ///  - Tag: synchronousDelete
    func deleteObject(identifiedBy objectIDs: [NSManagedObjectID]) {
        let viewContext = persistentContainer.viewContext
        debugPrint("Start deleting data from the store ...\(DebuggingIdentifiers.inProgress)")

        viewContext.perform {
            objectIDs.forEach { objectID in
                let entryToDelete = viewContext.object(with: objectID)
                viewContext.delete(entryToDelete)
            }
        }

        debugPrint("Successfully deleted data. \(DebuggingIdentifiers.succeeded)")
    }

    /// Asynchronously deletes records
    ///  - Tag: batchDelete
//    func batchDelete<T: NSManagedObject>(_ objects: [T]) async throws {
//        let objectIDs = objects.map(\.objectID)
//        let taskContext = newTaskContext()
//        // Add name and author to identify source of persistent history changes.
//        taskContext.name = "deleteContext"
//        taskContext.transactionAuthor = "batchDelete"
//        debugPrint("Start deleting data from the store... \(DebuggingIdentifiers.inProgress)")
//
//        try await taskContext.perform {
//            // Execute the batch delete.
//            let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: objectIDs)
//            guard let fetchResult = try? taskContext.execute(batchDeleteRequest),
//                  let batchDeleteResult = fetchResult as? NSBatchDeleteResult,
//                  let success = batchDeleteResult.result as? Bool, success
//            else {
//                debugPrint("Failed to execute batch delete request \(DebuggingIdentifiers.failed)")
//                throw CoreDataError.batchDeleteError
//            }
//        }
//
//        debugPrint("Successfully deleted data. \(DebuggingIdentifiers.succeeded)")
//    }
}

// MARK: - Save

extension NSManagedObjectContext {
    // takes a context as a parameter to be executed either on the main thread or on a background thread
    /// - Tag: save
    func saveContext(
        onContext: NSManagedObjectContext,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) throws {
        do {
            guard onContext.hasChanges else { return }
            try onContext.save()
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
