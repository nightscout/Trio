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
}
