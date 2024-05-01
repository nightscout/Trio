import CoreData
import Foundation

extension GlucoseStored {
    static func fetch(_ predicate: NSPredicate = .all, ascending: Bool, fetchLimit: Int? = nil) -> NSFetchRequest<GlucoseStored> {
        let request = GlucoseStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: ascending)]
        request.predicate = predicate
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        return request
    }

    static func glucoseIsFlat(_ glucose: [GlucoseStored]) -> Bool {
        guard glucose.count >= 3 else { return false }

        let lastThreeValues = glucose.suffix(3)
        let firstValue = lastThreeValues.last?.glucose

        return lastThreeValues.allSatisfy { $0.glucose == firstValue }
    }
}

extension NSPredicate {
    static var glucose: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "isManual == %@ AND date >= %@", false as NSNumber, date as NSDate)
    }

    static var manualGlucose: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "isManual == %@ AND date >= %@", true as NSNumber, date as NSDate)
    }
}

protocol GlucoseStoredObserver {
    func glucoseDidUpdate(_ glucose: [GlucoseStored])
}

extension GlucoseStored: Encodable {
    enum CodingKeys: String, CodingKey {
        case date
        case sgv
        case glucose
        case direction
        case id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let dateString = String(format: "%.0f", (date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000)
        try container.encode(dateString, forKey: .date)
        try container.encode(direction, forKey: .direction)
        try container.encode(id, forKey: .id)

        if isManual {
            try container.encode(glucose, forKey: .glucose)
        } else {
            try container.encode(glucose, forKey: .sgv)
        }
    }
}
