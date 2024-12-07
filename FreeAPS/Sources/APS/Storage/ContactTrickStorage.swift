import CoreData
import Foundation
import Swinject

protocol ContactTrickStorage {
    func fetchContactTrickEntryIds() async -> [NSManagedObjectID]
    func storeContactTrickEntry(_ entry: ContactTrickEntry) async
    func deleteContactTrickEntry(_ objectID: NSManagedObjectID) async
}

final class BaseContactTrickStorage: ContactTrickStorage, Injectable {
    @Injected() private var settingsManager: SettingsManager!

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func fetchContactTrickEntryIds() async -> [NSManagedObjectID] {
        // TODO: implement
        []
    }

    func storeContactTrickEntry(_: ContactTrickEntry) async {
        // TODO: implement
    }

    func deleteContactTrickEntry(_: NSManagedObjectID) async {
        // TODO: implement
    }
}
