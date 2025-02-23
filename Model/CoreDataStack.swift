import CoreData
import Foundation
import OSLog

class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    static let identifier = "CoreDataStack"

    private var notificationToken: NSObjectProtocol?
    private let inMemory: Bool

    let persistentContainer: NSPersistentContainer
    
    private init(inMemory: Bool = false) {
            self.inMemory = inMemory

            // Initialize persistent container immediately
            persistentContainer = NSPersistentContainer(
                name: "TrioCoreDataPersistentContainer",
                managedObjectModel: Self.managedObjectModel
            )

            guard let description = persistentContainer.persistentStoreDescriptions.first else {
                fatalError("Failed \(DebuggingIdentifiers.failed) to retrieve a persistent store description")
            }

            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }

            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true

            persistentContainer.loadPersistentStores { _, error in
                if let error = error as NSError? {
                    fatalError("Unresolved Error \(DebuggingIdentifiers.failed) \(error), \(error.userInfo)")
                }
            }

            persistentContainer.viewContext.automaticallyMergesChangesFromParent = false
            persistentContainer.viewContext.name = "viewContext"
            persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            persistentContainer.viewContext.undoManager = nil
            persistentContainer.viewContext.shouldDeleteInaccessibleFaults = true

            notificationToken = Foundation.NotificationCenter.default.addObserver(
                forName: .NSPersistentStoreRemoteChange,
                object: nil,
                queue: nil
            ) { _ in
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
    /// Save the last token to User defaults
    private var lastToken: NSPersistentHistoryToken? {
        get {
            UserDefaults.standard.lastHistoryToken
        }
        set {
            UserDefaults.standard.lastHistoryToken = newValue
        }
    }

    // Factory method for tests
    static func createForTests() -> CoreDataStack {
        CoreDataStack(inMemory: true)
    }

    // Used for Canvas Preview
    static var preview: CoreDataStack = {
        let stack = CoreDataStack(inMemory: true)
        let context = stack.persistentContainer.viewContext

        let pumpHistory = PumpEventStored.makePreviewEvents(count: 10, provider: stack)

        return stack
    }()

    // Shared managed object model
    static var managedObjectModel: NSManagedObjectModel = {
        let bundle = Bundle(for: CoreDataStack.self)
        guard let url = bundle.url(forResource: "TrioCoreDataPersistentContainer", withExtension: "momd") else {
            fatalError("Failed \(DebuggingIdentifiers.failed) to locate momd file")
        }

        guard let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed \(DebuggingIdentifiers.failed) to load momd file")
        }

        return model
    }()

    /// Creates and configures a private queue context
    func newTaskContext() -> NSManagedObjectContext {
        // Create a private queue context
        /// - Tag: newBackgroundContext
        let taskContext = persistentContainer.newBackgroundContext()

        /// ensure that the background contexts stay in sync with the main context
        taskContext.automaticallyMergesChangesFromParent = false
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        taskContext.undoManager = nil
        return taskContext
    }

    func fetchPersistentHistory() async {
        do {
            try await fetchPersistentHistoryTransactionsAndChanges()
        } catch {
            debug(.coreData, "\(error.localizedDescription)")
        }
    }

    private func fetchPersistentHistoryTransactionsAndChanges() async throws {
        let taskContext = newTaskContext()
        taskContext.name = "persistentHistoryContext"
//        debug(.coreData,"Start fetching persistent history changes from the store ... \(DebuggingIdentifiers.inProgress)")

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
//        debug(.coreData,"Received \(history.count) persistent history transactions")
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

    // Clean old Persistent History
    /// - Tag: clearHistory
    func cleanupPersistentHistoryTokens(before date: Date) async {
        let taskContext = newTaskContext()
        taskContext.name = "cleanPersistentHistoryTokensContext"

        await taskContext.perform {
            let deleteHistoryTokensRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: date)
            do {
                try taskContext.execute(deleteHistoryTokensRequest)
                debug(.coreData, "\(DebuggingIdentifiers.succeeded) Successfully deleted persistent history from before \(date)")
            } catch {
                debug(
                    .coreData,
                    "\(DebuggingIdentifiers.failed) Failed to delete persistent history from before \(date): \(error.localizedDescription)"
                )
            }
        }
    }

    func initializeStack() throws {
        // Force initialization of persistent container
        let container = persistentContainer

        // Verify the store is loaded
        guard container.persistentStoreCoordinator.persistentStores.isEmpty == false else {
            throw CoreDataError.storeNotInitializedError(function: #function, file: #file)
        }
    }
}

// MARK: - Delete

extension CoreDataStack {
    /// Synchronously delete entry with specified object IDs
    ///  - Tag: synchronousDelete
    func deleteObject(identifiedBy objectID: NSManagedObjectID) async {
        let viewContext = persistentContainer.viewContext
        debug(.coreData, "Start deleting data from the store ...\(DebuggingIdentifiers.inProgress)")

        await viewContext.perform {
            do {
                let entryToDelete = viewContext.object(with: objectID)
                viewContext.delete(entryToDelete)

                guard viewContext.hasChanges else { return }
                try viewContext.save()
                debug(.coreData, "Successfully deleted data. \(DebuggingIdentifiers.succeeded)")
            } catch {
                debug(.coreData, "Failed to delete data: \(error.localizedDescription)")
            }
        }
    }

    /// Asynchronously deletes records for entities
    ///  - Tag: batchDelete
    func batchDeleteOlderThan<T: NSManagedObject>(
        _ objectType: T.Type,
        dateKey: String,
        days: Int,
        isPresetKey: String? = nil,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) async throws {
        let taskContext = newTaskContext()
        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "batchDelete"

        // Get the number of days we want to keep the data
        let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        // Fetch all the objects that are older than the specified days
        let fetchRequest = NSFetchRequest<NSManagedObjectID>(entityName: String(describing: objectType))

        // Construct the predicate
        var predicates: [NSPredicate] = [NSPredicate(format: "%K < %@", dateKey, targetDate as NSDate)]
        if let isPresetKey = isPresetKey {
            predicates.append(NSPredicate(format: "%K == NO", isPresetKey))
        }
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        fetchRequest.resultType = .managedObjectIDResultType

        do {
            // Execute the Fetch Request
            let objectIDs = try await taskContext.perform {
                try taskContext.fetch(fetchRequest)
            }

            // Guard check if there are NSManagedObjects older than the specified days
            guard !objectIDs.isEmpty else {
//                debug(.coreData,"No objects found older than \(days) days.")
                return
            }

            // Execute the Batch Delete
            try await taskContext.perform {
                let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: objectIDs)
                guard let fetchResult = try? taskContext.execute(batchDeleteRequest),
                      let batchDeleteResult = fetchResult as? NSBatchDeleteResult,
                      let success = batchDeleteResult.result as? Bool, success
                else {
                    debug(.coreData, "Failed to execute batch delete request \(DebuggingIdentifiers.failed)")
                    throw CoreDataError.batchDeleteError(function: callingFunction, file: callingClass)
                }
            }

            debug(.coreData, "Successfully deleted data older than \(days) days. \(DebuggingIdentifiers.succeeded)")
        } catch {
            debug(.coreData, "Failed to fetch or delete data: \(error.localizedDescription) \(DebuggingIdentifiers.failed)")
            throw CoreDataError.unexpectedError(error: error, function: callingFunction, file: callingClass)
        }
    }

    func batchDeleteOlderThan<Parent: NSManagedObject, Child: NSManagedObject>(
        parentType: Parent.Type,
        childType: Child.Type,
        dateKey: String,
        days: Int,
        relationshipKey: String, // The key of the Child Entity that links to the parent Entity
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) async throws {
        let taskContext = newTaskContext()
        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "batchDelete"

        // Get the target date
        let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        // Fetch Parent objects older than the target date
        let fetchParentRequest = NSFetchRequest<NSManagedObjectID>(entityName: String(describing: parentType))
        fetchParentRequest.predicate = NSPredicate(format: "%K < %@", dateKey, targetDate as NSDate)
        fetchParentRequest.resultType = .managedObjectIDResultType

        do {
            let parentObjectIDs = try await taskContext.perform {
                try taskContext.fetch(fetchParentRequest)
            }

            guard !parentObjectIDs.isEmpty else {
//                debug(.coreData,"No \(parentType) objects found older than \(days) days.")
                return
            }

            // Fetch Child objects related to the fetched Parent objects
            let fetchChildRequest = NSFetchRequest<NSManagedObjectID>(entityName: String(describing: childType))
            fetchChildRequest.predicate = NSPredicate(format: "ANY %K IN %@", relationshipKey, parentObjectIDs)
            fetchChildRequest.resultType = .managedObjectIDResultType

            let childObjectIDs = try await taskContext.perform {
                try taskContext.fetch(fetchChildRequest)
            }

            guard !childObjectIDs.isEmpty else {
//                debug(.coreData,"No \(childType) objects found related to \(parentType) objects older than \(days) days.")
                return
            }

            // Execute the batch delete for Child objects
            try await taskContext.perform {
                let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: childObjectIDs)
                guard let fetchResult = try? taskContext.execute(batchDeleteRequest),
                      let batchDeleteResult = fetchResult as? NSBatchDeleteResult,
                      let success = batchDeleteResult.result as? Bool, success
                else {
                    debug(.coreData, "Failed to execute batch delete request \(DebuggingIdentifiers.failed)")
                    throw CoreDataError.batchDeleteError(function: callingFunction, file: callingClass)
                }
            }

            debug(
                .coreData,
                "Successfully deleted \(childType) data related to \(parentType) objects older than \(days) days. \(DebuggingIdentifiers.succeeded)"
            )
        } catch {
            debug(.coreData, "Failed to fetch or delete data: \(error.localizedDescription) \(DebuggingIdentifiers.failed)")
            throw CoreDataError.unexpectedError(error: error, function: callingFunction, file: callingClass)
        }
    }
}

// MARK: - Fetch Requests

extension CoreDataStack {
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
    ) throws -> [Any] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: type))
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        request.predicate = predicate
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        if let batchSize = batchSize {
            request.fetchBatchSize = batchSize
        }
        if let propertiesToFetch = propertiesToFetch {
            request.propertiesToFetch = propertiesToFetch
            request.resultType = .dictionaryResultType
        } else {
            request.resultType = .managedObjectResultType
        }

        context.name = "fetchContext"
        context.transactionAuthor = "fetchEntities"

        /// we need to ensure that the fetch immediately returns a value as long as the whole app does not use the async await pattern, otherwise we could perform this asynchronously with backgroundContext.perform and not block the thread
        return try context.performAndWait {
            do {
                if propertiesToFetch != nil {
                    return try context.fetch(request) as? [[String: Any]] ?? []
                } else {
                    return try context.fetch(request) as? [T] ?? []
                }
            } catch let error as NSError {
                throw CoreDataError.fetchError(
                    function: callingFunction,
                    file: callingClass
                )
            }
        }
    }

    // Fetch Async
    func fetchEntitiesAsync<T: NSManagedObject>(
        ofType type: T.Type,
        onContext context: NSManagedObjectContext,
        predicate: NSPredicate,
        key: String,
        ascending: Bool,
        fetchLimit: Int? = nil,
        batchSize: Int? = nil,
        propertiesToFetch: [String]? = nil,
        relationshipKeyPathsForPrefetching: [String]? = nil,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) async throws -> Any {
        let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: String(describing: type))
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        request.predicate = predicate

        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        if let batchSize = batchSize {
            request.fetchBatchSize = batchSize
        }
        if let propertiesToFetch = propertiesToFetch {
            request.propertiesToFetch = propertiesToFetch
            request.resultType = .dictionaryResultType
        } else {
            request.resultType = .managedObjectResultType
        }
        if let prefetchKeyPaths = relationshipKeyPathsForPrefetching {
            request.relationshipKeyPathsForPrefetching = prefetchKeyPaths
        }

        context.name = "fetchContext"
        context.transactionAuthor = "fetchEntities"

        return try await context.perform {
            do {
                if propertiesToFetch != nil {
                    return try context.fetch(request) as? [[String: Any]] ?? []
                } else {
                    return try context.fetch(request) as? [T] ?? []
                }
            } catch let error as NSError {
                throw CoreDataError.unexpectedError(
                    error: error,
                    function: callingFunction,
                    file: callingClass
                )
            }
        }
    }

    // Get NSManagedObject
    func getNSManagedObject<T: NSManagedObject>(
        with ids: [NSManagedObjectID],
        context: NSManagedObjectContext,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) async throws -> [T] {
        try await context.perform {
            var objects = [T]()
            do {
                for id in ids {
                    if let object = try context.existingObject(with: id) as? T {
                        objects.append(object)
                    }
                }
                return objects
            } catch {
                throw CoreDataError.fetchError(
                    function: callingFunction,
                    file: callingClass
                )
            }
        }
    }
}

// MARK: - Save

/// This function is used when terminating the App to ensure any unsaved changes on the view context made their way to the persistent container
extension CoreDataStack {
    func save() {
        let context = persistentContainer.viewContext

        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            debug(.coreData, "Error saving context \(DebuggingIdentifiers.failed): \(error)")
        }
    }
}

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
            debug(.coreData,
                "Saving to Core Data successful in \(callingFunction) in \(callingClass): \(DebuggingIdentifiers.succeeded)"
            )
        } catch let error as NSError {
            debug(
                .coreData,
                "Saving to Core Data failed in \(callingFunction) in \(callingClass): \(DebuggingIdentifiers.failed) with error \(error), \(error.userInfo)"
            )
            throw error
        }
    }
}
