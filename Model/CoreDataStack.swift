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
}
