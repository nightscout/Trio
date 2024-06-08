import CoreData
import Foundation

class CoreDataStack: ObservableObject {
    public static let modelName = "Core_Data"

    public static let model: NSManagedObjectModel = {
        let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: modelURL)!
    }()

    init() {}

    static let shared = CoreDataStack()

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: CoreDataStack.modelName)

        container.loadPersistentStores(completionHandler: { _, error in
            guard let error = error as NSError? else { return }
            fatalError("Unresolved error: \(error), \(error.userInfo)")
        })

        return container
    }()

    func saveContext() {
        let context = persistentContainer.viewContext

        context.perform {
            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    // Replace this implementation with code to handle the error appropriately.
                    // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping    application, although it may be useful during development.
                    let nserror = error as NSError
                    fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
                }
            }
        }
    }

    func delete(obj: NSManagedObject) {
        persistentContainer.viewContext.delete(obj)
    }
}
