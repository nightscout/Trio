import CoreData
import Foundation

public final class NSModelObjectContextExecutor: @unchecked Sendable, SerialExecutor {
    public let context: NSManagedObjectContext

    public init(context: NSManagedObjectContext) {
        self.context = context
    }

    // Enqueue the job to the context's queue.
    public func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let unownedExecutor = asUnownedSerialExecutor()
        context.perform {
            unownedJob.runSynchronously(on: unownedExecutor)
        }
    }

    // Return an unowned serial executor reference.
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

// A protocol to define common functionalities for Core Data-based actors
protocol CoreDataActor {
    var modelExecutor: NSModelObjectContextExecutor { get }
    var modelContainer: NSPersistentContainer { get }
}

// Extend the protocol with default implementations and helpers
extension CoreDataActor {
    public var modelContext: NSManagedObjectContext {
        modelExecutor.context
    }

    public var unownedExecutor: UnownedSerialExecutor {
        modelExecutor.asUnownedSerialExecutor()
    }

    // Provide a generic subscript to fetch objects by NSManagedObjectID
    public subscript<T>(id: NSManagedObjectID, as _: T.Type) -> T? where T: NSManagedObject {
        try? modelContext.existingObject(with: id) as? T
    }
}
