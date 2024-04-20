import CoreData
import Foundation

public extension Oref0Suggestion {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Oref0Suggestion> {
        NSFetchRequest<Oref0Suggestion>(entityName: "Oref0Suggestion")
    }

    @NSManaged var computedInsulinDistribution: NSSet?
    @NSManaged var computedTDD: NSSet?
}

// MARK: Generated accessors for computedInsulinDistribution

public extension Oref0Suggestion {
    @objc(addComputedInsulinDistributionObject:)
    @NSManaged func addToComputedInsulinDistribution(_ value: InsulinDistribution)

    @objc(removeComputedInsulinDistributionObject:)
    @NSManaged func removeFromComputedInsulinDistribution(_ value: InsulinDistribution)

    @objc(addComputedInsulinDistribution:)
    @NSManaged func addToComputedInsulinDistribution(_ values: NSSet)

    @objc(removeComputedInsulinDistribution:)
    @NSManaged func removeFromComputedInsulinDistribution(_ values: NSSet)
}

// MARK: Generated accessors for computedTDD

public extension Oref0Suggestion {
    @objc(addComputedTDDObject:)
    @NSManaged func addToComputedTDD(_ value: TDD)

    @objc(removeComputedTDDObject:)
    @NSManaged func removeFromComputedTDD(_ value: TDD)

    @objc(addComputedTDD:)
    @NSManaged func addToComputedTDD(_ values: NSSet)

    @objc(removeComputedTDD:)
    @NSManaged func removeFromComputedTDD(_ values: NSSet)
}

extension Oref0Suggestion: Identifiable {}
