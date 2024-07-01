import Foundation

// Fetch Data for Glucose and Determination from Core Data and map them to the Structs in order to pass them thread safe to the glucoseDidUpdate/ pushUpdate function

@available(iOS 16.2, *)
extension LiveActivityBridge {
    func fetchAndMapGlucose() async {
        let result = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForSixHoursAgo,
            key: "date",
            ascending: false,
            fetchLimit: 72
        )
        await context.perform {
            self.glucoseFromPersistence = result
                .map { GlucoseData(glucose: Int($0.glucose), date: $0.date ?? Date(), direction: $0.directionEnum) }
        }
    }

    func fetchAndMapDetermination() async {
        let result = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.enactedDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["iob", "cob", "deliverAt"]
        )
        await context.perform {
            self.determination = result.first.map { DeterminationData(cob: Int($0.cob), iob: $0.iob?.decimalValue ?? 0) }
        }
    }

    func fetchAndMapOverride() async {
        let result = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false,
            fetchLimit: 1
        )
        await context.perform {
            self.isOverridesActive = result.first.map { OverrideData(isActive: $0.enabled) }
        }
    }
}
