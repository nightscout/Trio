import Combine
import CoreData
import Foundation

// The app-wide Core Data change feed now lives on `CoreDataStack.entityChangePublisher`, which is
// sourced from persistent history (and therefore also covers batch operations and cross-process
// changes). This file only keeps the `filteredByEntityName` operator used by its subscribers.

extension Publisher where Output == Set<NSManagedObjectID> {
    /// Filters Core Data changes by entity name.
    ///
    /// Example usage:
    /// ```swift
    /// // Filter changes for "GlucoseStored" entity
    /// CoreDataStack.shared.entityChangePublisher.filteredByEntityName("GlucoseStored")
    /// ```
    ///
    /// - Parameter name: The name of the Core Data entity to filter for
    /// - Returns: A publisher emitting filtered sets of NSManagedObjectIDs
    func filteredByEntityName(
        _ name: String
    ) -> some Publisher<Set<NSManagedObjectID>, Self.Failure> {
        compactMap { objectIDs -> Set<NSManagedObjectID>? in
            // Early exit for empty sets
            guard !objectIDs.isEmpty else { return nil }

            // Use lazy evaluation for better performance
            let filtered = objectIDs.lazy.filter { $0.entity.name == name }
            let result = Set(filtered)
            return result.isEmpty ? nil : result
        }
    }
}
