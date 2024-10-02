import Foundation

// Fetch Data for Glucose and Determination from Core Data and map them to the Structs in order to pass them thread safe to the glucoseDidUpdate/ pushUpdate function

@available(iOS 16.2, *)
extension LiveActivityBridge {
    func fetchAndMapGlucose() async {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForSixHoursAgo,
            key: "date",
            ascending: false,
            fetchLimit: 72
        )

        await context.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                return
            }

            self.glucoseFromPersistence = glucoseResults.map {
                GlucoseData(glucose: Int($0.glucose), date: $0.date ?? Date(), direction: $0.directionEnum)
            }
        }
    }

    func fetchAndMapDetermination() async {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["iob", "cob", "currentTarget"]
        )

        await context.perform {
            guard let determinationResults = results as? [[String: Any]] else {
                return
            }

            self.determination = determinationResults.first.map {
                DeterminationData(
                    cob: ($0["cob"] as? Int) ?? 0,
                    iob: ($0["iob"] as? NSDecimalNumber)?.decimalValue ?? 0,
                    target: ($0["currentTarget"] as? NSDecimalNumber)?.decimalValue ?? 0
                )
            }
        }
    }

    func fetchAndMapOverride() async {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["enabled", "name", "target", "date", "duration"]
        )

        await context.perform {
            guard let overrideResults = results as? [[String: Any]] else {
                return
            }

            self.isOverridesActive = overrideResults.first.map {
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
