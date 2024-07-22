import CoreData
import Foundation

class CoreDataObserver {
    private var entityUpdateHandlers: [String: () -> Void] = [:] // Dictionary to store pairs of entities and handlers

    init() {
        setupNotification()
    }

    func registerHandler(for entityName: String, handler: @escaping () -> Void) {
        entityUpdateHandlers[entityName] = handler
    }

    private func setupNotification() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: NSNotification.Name.NSManagedObjectContextDidSave,
            object: nil
        )
    }

    @objc private func contextDidSave(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        Task {
            await processUpdates(userInfo: userInfo)
        }
    }

    private func processUpdates(userInfo: [AnyHashable: Any]) async {
        var objects = Set((userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? [])
        objects.formUnion((userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? [])
        objects.formUnion((userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? [])

        for (entityName, handler) in entityUpdateHandlers {
            let entityUpdates = objects.filter { $0.entity.name == entityName }
            DispatchQueue.global(qos: .background).async {
                if entityUpdates.isNotEmpty {
                    handler()
                }
            }
        }
    }
}
