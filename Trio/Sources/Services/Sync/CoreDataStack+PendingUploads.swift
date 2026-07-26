import CoreData
import Foundation

extension CoreDataStack {
    /// Fetches entities matching a backend's "not yet uploaded" predicate and maps them
    /// to upload payloads on the context's queue.
    ///
    /// One shared implementation of the fetch/cast/map step behind every storage
    /// `get<X>NotYetUploadedTo<Backend>()` method. `map` runs inside `context.perform`,
    /// so it may safely read managed objects; entities mapped to nil are dropped.
    func fetchPendingUploads<Entity: NSManagedObject, Output>(
        ofType type: Entity.Type,
        onContext context: NSManagedObjectContext,
        predicate: NSPredicate,
        key: String = "date",
        ascending: Bool = false,
        relationshipKeyPathsForPrefetching: [String]? = nil,
        callingFunction: String = #function,
        callingClass: String = #fileID,
        map: @escaping (Entity) -> Output?
    ) async throws -> [Output] {
        let results = try await fetchEntitiesAsync(
            ofType: type,
            onContext: context,
            predicate: predicate,
            key: key,
            ascending: ascending,
            relationshipKeyPathsForPrefetching: relationshipKeyPathsForPrefetching,
            callingFunction: callingFunction,
            callingClass: callingClass
        )

        return try await context.perform {
            guard let entities = results as? [Entity] else {
                throw CoreDataError.fetchError(function: callingFunction, file: callingClass)
            }
            return entities.compactMap(map)
        }
    }
}
