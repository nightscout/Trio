import CoreData
import Foundation

public extension PhysioTestStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PhysioTestStored> {
        NSFetchRequest<PhysioTestStored>(entityName: "PhysioTestStored")
    }

    @NSManaged var absorptionDuration: Double
    @NSManaged var baselineGlucose: Double
    @NSManaged var bolusAmount: Double
    @NSManaged var bolusTime: Date?
    @NSManaged var carbs: Double
    @NSManaged var endDate: Date?
    @NSManaged var fat: Double
    @NSManaged var glucoseReadings: Data?
    @NSManaged var id: UUID?
    @NSManaged var isComplete: Bool
    @NSManaged var mealTime: Date?
    @NSManaged var notes: String?
    @NSManaged var onsetDelay: Double
    @NSManaged var peakAbsorptionRate: Double
    @NSManaged var peakGlucose: Double
    @NSManaged var protein: Double
    @NSManaged var seriesID: UUID?
    @NSManaged var startDate: Date?
    @NSManaged var testType: String?
    @NSManaged var timeToPeak: Double
    @NSManaged var totalAUC: Double
}

extension PhysioTestStored: Identifiable {}

extension PhysioTestStored {
    static func fetch(
        _ predicate: NSPredicate,
        ascending: Bool,
        fetchLimit: Int? = nil
    ) -> NSFetchRequest<PhysioTestStored> {
        let request = PhysioTestStored.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: ascending)]
        if let fetchLimit = fetchLimit {
            request.fetchLimit = fetchLimit
        }
        return request
    }
}
