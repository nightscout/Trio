import Foundation

// Fetch Data for Glucose and Determination from Core Data and map them to the Structs in order to pass them thread safe to the glucoseDidUpdate/ pushUpdate function

@available(iOS 16.2, *)
extension LiveActivityBridge {
    func fetchAndMapGlucose() async {
        await context.perform {
            self.glucoseFromPersistence = CoreDataStack.shared.fetchEntities(
                ofType: GlucoseStored.self,
                onContext: self.context,
                predicate: NSPredicate.predicateForSixHoursAgo,
                key: "date",
                ascending: false,
                fetchLimit: 72
            ).map { GlucoseData(glucose: Int($0.glucose), date: $0.date ?? Date(), direction: $0.directionEnum) }
        }
    }

    func fetchAndMapDetermination() async {
        await context.perform {
            self.determination = CoreDataStack.shared.fetchEntities(
                ofType: OrefDetermination.self,
                onContext: self.context,
                predicate: NSPredicate.enactedDetermination,
                key: "deliverAt",
                ascending: false,
                fetchLimit: 1,
                propertiesToFetch: ["iob", "cob", "deliverAt"]
            ).first.map { DeterminationData(cob: Int($0.cob), iob: $0.iob?.decimalValue ?? 0) }
        }
    }
}
