import CoreData
import Foundation

extension NSPredicate {
    static var fpusForChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "isFPU == true AND date >= %@", date as NSDate)
    }

    static var carbsForChart: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "isFPU == false AND date >= %@ AND carbs > 0", date as NSDate)
    }

    static var carbsForStats: NSPredicate {
        let date = Date.threeMonthsAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var carbsNotYetUploadedToNightscout: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToNS == %@ AND isFPU == %@ AND carbs > 0",
            date as NSDate,
            false as NSNumber,
            false as NSNumber
        )
    }

    static var carbsNotYetUploadedToHealth: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToHealth == %@",
            date as NSDate,
            false as NSNumber
        )
    }

    static var carbsNotYetUploadedToTidepool: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToTidepool == %@",
            date as NSDate,
            false as NSNumber
        )
    }

    static var fpusNotYetUploadedToNightscout: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToNS == %@ AND isFPU == %@",
            date as NSDate,
            false as NSNumber,
            true as NSNumber
        )
    }
}

extension CarbEntryStored {
    static func fetch(
        _ predicate: NSPredicate = .predicateForOneDayAgo,
        fetchLimit: Int = 100,
        ascending: Bool = false
    ) -> NSFetchRequest<CarbEntryStored> {
        let request = CarbEntryStored.fetchRequest() as NSFetchRequest<CarbEntryStored>
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CarbEntryStored.date, ascending: ascending)]
        request.fetchLimit = fetchLimit
        request.predicate = predicate
        return request
    }
}

extension CarbEntryStored: Encodable {
    enum CodingKeys: String, CodingKey {
        case actualDate
        case created_at
        case carbs
        case fat
        case id
        case isFPU
        case note
        case protein
        case enteredBy
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let formattedDate = dateFormatter.string(from: date ?? Date())
        try container.encode(formattedDate, forKey: .actualDate)
        try container.encode(formattedDate, forKey: .created_at)

        // TODO: handle this conditionally; pass in the enteredBy string (manual entry or via NS or Apple Health)
        try container.encode("Trio", forKey: .enteredBy)

        try container.encode(carbs, forKey: .carbs)
        try container.encode(fat, forKey: .fat)
        try container.encode(isFPU, forKey: .isFPU)
        try container.encode(note, forKey: .note)
        try container.encode(protein, forKey: .protein)
        try container.encode(id, forKey: .id)
    }
}
