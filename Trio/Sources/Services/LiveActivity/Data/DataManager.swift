import CoreData
import Foundation

// Fetch Data for Glucose and Determination from Core Data and map them to the Structs in order to pass them thread safe to the glucoseDidUpdate/ pushUpdate function

@available(iOS 16.2, *)
extension LiveActivityManager {
    func fetchAndMapGlucose() async throws -> [GlucoseData] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchAndMapGlucose"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForSixHoursAgo,
            key: "date",
            ascending: false,
            fetchLimit: 72
        )

        return try await context.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return glucoseResults.map {
                GlucoseData(glucose: Int($0.glucose), date: $0.date ?? Date(), direction: $0.directionEnum)
            }
        }
    }

    // TODO: extract logic or at least rename function appropiately
    func fetchAndMapDetermination() async throws -> DeterminationData? {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchAndMapDetermination"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["cob", "currentTarget", "deliverAt"]
        )

        let tddResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["total"]
        )

        return try await context.perform {
            guard let determinationResults = results as? [[String: Any]], let tddResults = tddResults as? [[String: Any]] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            guard let determination = determinationResults.first else {
                return nil
            }

            let tddValue = (tddResults.first?["total"] as? NSDecimalNumber)?.decimalValue ?? 0

            return DeterminationData(
                cob: (determination["cob"] as? Int) ?? 0,
                tdd: tddValue,
                target: (determination["currentTarget"] as? NSDecimalNumber)?.decimalValue ?? 0,
                date: determination["deliverAt"] as? Date ?? nil
            )
        }
    }

    func fetchAndMapTempTarget() async throws -> TempTargetData? {
        try await fetchAndMapLatest(
            ofType: TempTargetStored.self,
            predicate: .predicateForOneDayAgo,
            key: "date",
            propertiesToFetch: ["enabled", "name", "target", "date", "duration"]
        ) { row in
            TempTargetData(
                isActive: row["enabled"] as? Bool ?? false,
                tempTargetName: row["name"] as? String ?? "Temp Target",
                date: row["date"] as? Date ?? Date(),
                duration: row["duration"] as? Decimal ?? 0,
                target: row["target"] as? Decimal ?? 0
            )
        }
    }

    func fetchAndMapOverride() async throws -> OverrideData? {
        try await fetchAndMapLatest(
            ofType: OverrideStored.self,
            predicate: .predicateForOneDayAgo,
            key: "date",
            propertiesToFetch: ["enabled", "name", "target", "date", "duration"]
        ) { row in
            OverrideData(
                isActive: row["enabled"] as? Bool ?? false,
                overrideName: row["name"] as? String ?? "Override",
                date: row["date"] as? Date ?? Date(),
                duration: row["duration"] as? Decimal ?? 0,
                target: row["target"] as? Decimal ?? 0
            )
        }
    }

    private func fetchAndMapLatest<Entity: NSManagedObject, Output>(
        ofType type: Entity.Type,
        predicate: NSPredicate,
        key: String,
        propertiesToFetch: [String],
        map: @escaping ([String: Any]) -> Output
    ) async throws -> Output? {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchAndMapLatest"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: type,
            onContext: context,
            predicate: predicate,
            key: key,
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: propertiesToFetch
        )

        return try await context.perform {
            guard let rows = results as? [[String: Any]] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return rows.first.map(map)
        }
    }
}
