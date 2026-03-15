import CoreData
import Foundation

extension Home.StateModel {
    func setupPhysioTests() {
        Task {
            do {
                let context = CoreDataStack.shared.newTaskContext()

                // Fetch active tests (not complete, has start date)
                let activeResults = try await CoreDataStack.shared.fetchEntitiesAsync(
                    ofType: PhysioTestStored.self,
                    onContext: context,
                    predicate: NSPredicate(format: "isComplete == NO AND startDate != nil"),
                    key: "startDate",
                    ascending: false
                )

                let activeIDs: [NSManagedObjectID] = try await context.perform {
                    guard let fetched = activeResults as? [PhysioTestStored] else {
                        throw CoreDataError.fetchError(function: #function, file: #file)
                    }
                    return fetched.map(\.objectID)
                }

                let activeObjects: [PhysioTestStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: activeIDs, context: viewContext)

                // Fetch completed tests from last 24 hours for chart display
                let completedResults = try await CoreDataStack.shared.fetchEntitiesAsync(
                    ofType: PhysioTestStored.self,
                    onContext: context,
                    predicate: NSPredicate(
                        format: "isComplete == YES AND startDate >= %@",
                        Date.oneDayAgo as NSDate
                    ),
                    key: "startDate",
                    ascending: false
                )

                let completedIDs: [NSManagedObjectID] = try await context.perform {
                    guard let fetched = completedResults as? [PhysioTestStored] else {
                        throw CoreDataError.fetchError(function: #function, file: #file)
                    }
                    return fetched.map(\.objectID)
                }

                let completedObjects: [PhysioTestStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: completedIDs, context: viewContext)

                await MainActor.run {
                    activePhysioTests = activeObjects
                    completedPhysioTests = completedObjects
                }
            } catch {
                debug(.default, "Error fetching physio tests: \(error)")
            }
        }
    }
}
