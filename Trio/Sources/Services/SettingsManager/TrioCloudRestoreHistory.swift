import CoreData
import Foundation

extension TrioCloudSettingsRestore {
    /// At most one imported sample per five-minute bucket. Existing local history wins.
    static func missingTDDHistory(
        _ history: [TrioSettingsBackup.TDDRecord],
        context: NSManagedObjectContext
    ) async throws -> [TrioSettingsBackup.TDDRecord] {
        guard !history.isEmpty else { return [] }
        // Preserve qualified local history; mixing in an older backup would change TDD averages.
        guard !(try await BaseTDDStorage.hasSufficientTDD(context: context)) else { return [] }
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "TDDStored")
            request.predicate = NSPredicate(
                format: "date >= %@ OR id IN %@",
                (history.map(\.date).min() ?? Date()).addingTimeInterval(-300) as NSDate,
                history.map(\.id)
            )
            let existing = try context.fetch(request)
            var ids = Set(existing.compactMap { $0.value(forKey: "id") as? UUID })
            var slots = Set(
                existing
                    .compactMap { ($0.value(forKey: "date") as? Date).map { Int($0.timeIntervalSince1970 / 300) } }
            )
            return history.sorted { $0.date < $1.date }.filter { row in
                let slot = Int(row.date.timeIntervalSince1970 / 300)
                guard !ids.contains(row.id), !slots.contains(slot) else { return false }
                ids.insert(row.id)
                slots.insert(slot)
                return true
            }
        }
    }

    static func insertTDDHistory(
        _ history: [TrioSettingsBackup.TDDRecord],
        context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            let previousAuthor = context.transactionAuthor
            context.transactionAuthor = "TrioCloudRestore"
            defer { context.transactionAuthor = previousAuthor }
            do {
                for sample in history {
                    let row = NSEntityDescription.insertNewObject(forEntityName: "TDDStored", into: context)
                    row.setValue(sample.id, forKey: "id")
                    row.setValue(sample.date, forKey: "date")
                    for (key, value) in [
                        ("total", sample.total),
                        ("bolus", sample.bolus),
                        ("tempBasal", sample.tempBasal),
                        ("scheduledBasal", sample.scheduledBasal),
                        ("weightedAverage", sample.weightedAverage)
                    ] {
                        row.setValue(NSDecimalNumber(decimal: value), forKey: key)
                    }
                }
                if context.hasChanges { try context.save() }
            } catch { context.rollback()
                throw error }
        }
    }


}
