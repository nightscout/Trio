import Combine
import CoreData
import Foundation

/// Represents the types of Core Data changes that can be observed
/// Use as an option set to specify which types of changes to monitor
public struct CoreDataChangeTypes: OptionSet {
    /// The raw integer value used to store the option set bits
    public let rawValue: Int

    /// Required initializer for OptionSet conformance
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Represents newly created/inserted objects in Core Data
    /// Binary: 001 (1 << 0)
    public static let inserted = CoreDataChangeTypes(rawValue: 1 << 0)

    /// Represents modified/updated objects in Core Data
    /// Binary: 010 (1 << 1)
    public static let updated = CoreDataChangeTypes(rawValue: 1 << 1)

    /// Represents removed/deleted objects in Core Data
    /// Binary: 100 (1 << 2)
    public static let deleted = CoreDataChangeTypes(rawValue: 1 << 2)

    /// Convenience option that includes all possible change types
    /// This combines inserted, updated, and deleted into a single option
    public static let all: CoreDataChangeTypes = [.inserted, .updated, .deleted]
}

/// Creates a publisher that emits sets of NSManagedObjectIDs when Core Data changes occur
/// - Parameter changeTypes: The types of changes to observe (defaults to .all)
/// - Returns: A publisher that emits Sets of NSManagedObjectIDs for the specified change types
func changedObjectsOnManagedObjectContextDidSavePublisher(
    observing changeTypes: CoreDataChangeTypes = .all
) -> some Publisher<Set<NSManagedObjectID>, Never> {
    Foundation.NotificationCenter.default
        .publisher(for: .NSManagedObjectContextDidSave)
        .compactMap { notification -> Set<NSManagedObjectID>? in

            var objectIDs = Set<NSManagedObjectID>()

            // Process inserted objects if requested
            if changeTypes.contains(.inserted) {
                objectIDs.formUnion(notification.insertedObjectIDs)
            }

            // Process updated objects if requested
            if changeTypes.contains(.updated) {
                objectIDs.formUnion(notification.updatedObjectIDs)
            }

            // Process deleted objects if requested
            if changeTypes.contains(.deleted) {
                objectIDs.formUnion(notification.deletedObjectIDs)
            }

            // Only emit non-empty sets
            return objectIDs.isEmpty ? nil : objectIDs
        }
}

extension Publisher where Output == Set<NSManagedObjectID> {
    /// Filters Core Data changes by entity name
    ///
    /// This method allows filtering Core Data changes by entity name.
    ///
    /// Example usage:
    /// ```swift
    /// // Filter changes for "GlucoseStored" entity
    /// publisher.filteredByEntityName("GlucoseStored")
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the Core Data entity to filter for
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

extension Notification {
    var insertedObjectIDs: Set<NSManagedObjectID> {
        guard let objects = userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return [] }
        return Set(objects.lazy.map(\.objectID))
    }

    var updatedObjectIDs: Set<NSManagedObjectID> {
        guard let objects = userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> else { return [] }
        return Set(objects.lazy.map(\.objectID))
    }

    var deletedObjectIDs: Set<NSManagedObjectID> {
        guard let objects = userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> else { return [] }
        return Set(objects.lazy.map(\.objectID))
    }
}
