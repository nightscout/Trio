import CoreData
import Foundation

extension NSPredicate {
    static var fpusForChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "fat > 0 AND protein > 0 AND isFPU == true AND date >= %@", date as NSDate)
    }

    static var carbsForChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "carbs > 0 AND isFPU == false AND date >= %@", date as NSDate)
    }
}

extension MealsStored {
    static func fetch(
        _ predicate: NSPredicate = .predicateForOneDayAgo,
        fetchLimit: Int = 100,
        ascending: Bool = false
    ) -> NSFetchRequest<MealsStored> {
        let request = MealsStored.fetchRequest() as NSFetchRequest<MealsStored>
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MealsStored.date, ascending: ascending)]
        request.fetchLimit = fetchLimit
        request.predicate = predicate
        return request
    }
}

extension MealsStored: Encodable {
    enum CodingKeys: String, CodingKey {
        case date
        case carbs
        case fat
        case id
        case isFPU
        case note
        case protein
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(date, forKey: .date)
        try container.encode(carbs, forKey: .carbs)
        try container.encode(fat, forKey: .fat)
        try container.encode(isFPU, forKey: .isFPU)
        try container.encode(note, forKey: .note)
        try container.encode(protein, forKey: .protein)
        try container.encode(id, forKey: .id)
    }
}
