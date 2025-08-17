import CoreData
import Foundation

extension AutoApplyOverride {
    final class Provider: BaseProvider, AutoApplyOverrideProvider {
        func getOverridePresets() -> [OverrideStored] {
            do {
                let request = OverrideStored.fetchRequest() as NSFetchRequest<OverrideStored>
                request.predicate = NSPredicate(format: "isPreset == true")
                request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

                let presets = try CoreDataStack.shared.persistentContainer.viewContext.fetch(request)
                return presets
            } catch {
                debug(.default, "Failed to fetch override presets: \(error)")
                return []
            }
        }

        func getActivityLog() -> [ActivityLogEntry] {
            storage.retrieve("activity_log.json", as: [ActivityLogEntry].self) ?? []
        }

        func clearActivityLog() {
            storage.save([ActivityLogEntry](), as: "activity_log.json")
        }
    }
}
