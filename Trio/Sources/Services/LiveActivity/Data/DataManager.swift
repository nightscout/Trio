import Foundation

// Fetch Data for Glucose and Determination from Core Data and map them to the Structs in order to pass them thread safe to the glucoseDidUpdate/ pushUpdate function

@available(iOS 16.2, *)
extension LiveActivityManager {
    func fetchAndMapGlucose() async throws -> [GlucoseData] {
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
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["iob", "cob", "currentTarget", "deliverAt"]
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
                iob: (determination["iob"] as? NSDecimalNumber)?.decimalValue ?? 0,
                tdd: tddValue,
                target: (determination["currentTarget"] as? NSDecimalNumber)?.decimalValue ?? 0,
                date: determination["deliverAt"] as? Date ?? nil
            )
        }
    }

    func fetchAndMapOverride() async throws -> OverrideData? {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["enabled", "name", "target", "date", "duration"]
        )

        return try await context.perform {
            guard let overrideResults = results as? [[String: Any]] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return overrideResults.first.map {
                OverrideData(
                    isActive: $0["enabled"] as? Bool ?? false,
                    overrideName: $0["name"] as? String ?? "Override",
                    date: $0["date"] as? Date ?? Date(),
                    duration: $0["duration"] as? Decimal ?? 0,
                    target: $0["target"] as? Decimal ?? 0
                )
            }
        }
    }
}
