import CoreData
import CryptoKit
import Foundation

extension TrioSettingsBackup {
    /// Historical TDD summary for Dynamic ISF; contains no delivery commands.
    struct TDDRecord: Codable, Equatable {
        let id: UUID
        let date: Date
        let total: Decimal
        let bolus: Decimal
        let tempBasal: Decimal
        let scheduledBasal: Decimal
        let weightedAverage: Decimal
    }

    static func historyDigest(_ history: [TDDRecord]) throws -> String {
        digest(try encoded(history))
    }

    static func readTDDHistory(
        context: NSManagedObjectContext = CoreDataStack.shared.newTaskContext(),
        now: Date = Date()
    ) async throws -> [TDDRecord] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "TDDStored")
            request.predicate = NSPredicate(
                format: "date >= %@ AND date <= %@ AND total > 0",
                now.addingTimeInterval(-10 * 86400) as NSDate,
                now as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            request.fetchLimit = 10000
            return try context.fetch(request).map { row in
                func decimal(_ key: String) -> Decimal {
                    (row.value(forKey: key) as? NSDecimalNumber)?.decimalValue ?? 0
                }
                return TDDRecord(
                    id: row.value(forKey: "id") as? UUID ?? UUID(),
                    date: row.value(forKey: "date") as! Date,
                    total: decimal("total"),
                    bolus: decimal("bolus"),
                    tempBasal: decimal("tempBasal"),
                    scheduledBasal: decimal("scheduledBasal"),
                    weightedAverage: decimal("weightedAverage")
                )
            }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        }
    }

    func eligibleTDDHistory(now: Date = Date()) -> [TDDRecord] {
        guard now >= createdAt else { return [] }
        return (dynamicISFHistory ?? []).filter { $0.date > now.addingTimeInterval(-10 * 86400) && $0.date <= now }
    }

    func validateHistory() throws {
        guard let history = dynamicISFHistory else {
            guard historyChecksum == nil else { throw BackupError.integrityCheckFailed }
            return
        }
        guard (4 ... Self.currentSchema).contains(schemaVersion), history.count <= 10000,
              historyChecksum == (try Self.historyDigest(history)),
              Set(history.map(\.id)).count == history.count else { throw BackupError.integrityCheckFailed }
        for row in history {
            let values = [row.total, row.bolus, row.tempBasal, row.scheduledBasal, row.weightedAverage]
            guard row.date <= createdAt, row.date >= createdAt.addingTimeInterval(-10 * 86400),
                  row.date.timeIntervalSinceReferenceDate.isFinite,
                  values.allSatisfy({ !$0.isNaN && $0 >= 0 }), row.total > 0
            else {
                throw BackupError.invalidTherapyConfiguration
            }
        }
    }


}
