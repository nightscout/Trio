import CoreData
import Foundation
import Swinject

protocol PhysioTestStorage {
    func storeTest(_ test: PhysioTestStored) async throws
    func fetchActiveTest() async throws -> NSManagedObjectID?
    func fetchAllTests() async throws -> [NSManagedObjectID]
    func fetchTestsForSeries(_ seriesID: UUID) async throws -> [NSManagedObjectID]
    func deleteTest(_ objectID: NSManagedObjectID) async
}

final class BasePhysioTestStorage: @preconcurrency PhysioTestStorage, Injectable {
    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let context: NSManagedObjectContext

    init(resolver: Resolver, context: NSManagedObjectContext? = nil) {
        self.context = context ?? CoreDataStack.shared.newTaskContext()
        injectServices(resolver)
    }

    func storeTest(_ test: PhysioTestStored) async throws {
        try await context.perform {
            guard self.context.hasChanges else { return }
            try self.context.save()
        }
    }

    func fetchActiveTest() async throws -> NSManagedObjectID? {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PhysioTestStored.self,
            onContext: context,
            predicate: NSPredicate(format: "isComplete == NO AND startDate != nil"),
            key: "startDate",
            ascending: false,
            fetchLimit: 1
        )

        return try await context.perform {
            guard let fetched = results as? [PhysioTestStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetched.first?.objectID
        }
    }

    func fetchAllTests() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PhysioTestStored.self,
            onContext: context,
            predicate: NSPredicate(value: true),
            key: "startDate",
            ascending: false
        )

        return try await context.perform {
            guard let fetched = results as? [PhysioTestStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetched.map(\.objectID)
        }
    }

    func fetchTestsForSeries(_ seriesID: UUID) async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PhysioTestStored.self,
            onContext: context,
            predicate: NSPredicate(format: "seriesID == %@", seriesID as CVarArg),
            key: "startDate",
            ascending: true
        )

        return try await context.perform {
            guard let fetched = results as? [PhysioTestStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetched.map(\.objectID)
        }
    }

    func deleteTest(_ objectID: NSManagedObjectID) async {
        let taskContext = CoreDataStack.shared.newTaskContext()
        taskContext.name = "deletePhysioTestContext"

        await taskContext.perform {
            do {
                guard let test = try taskContext.existingObject(with: objectID) as? PhysioTestStored else {
                    return
                }
                taskContext.delete(test)
                guard taskContext.hasChanges else { return }
                try taskContext.save()
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error deleting physio test: \(error)")
            }
        }
    }
}
