import CoreData
import Foundation

extension GlucoseStored {
    static func fetch(
        _ predicate: NSPredicate = .all,
        ascending: Bool,
        fetchLimit: Int? = nil,
        batchSize: Int? = nil
    ) -> NSFetchRequest<GlucoseStored> {
        let request = GlucoseStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: ascending)]
        request.predicate = predicate
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        if let batchSize = batchSize {
            request.fetchBatchSize = batchSize
        }
        return request
    }

    static func glucoseIsFlat(_ glucose: [GlucoseStored]) -> Bool {
        guard glucose.count >= 4 else { return false }

        let lastThreeValues = glucose.suffix(4)
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

    static var glucoseForStatsDay: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var glucoseForStatsToday: NSPredicate {
        let date = Date.startOfToday
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var glucoseForStatsMonth: NSPredicate {
        let date = Date.oneMonthAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var glucoseForStatsTotal: NSPredicate {
        let date = Date.threeMonthsAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var glucoseForStatsWeek: NSPredicate {
        let date = Date.oneWeekAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }
}

extension GlucoseStored: Encodable {
    enum CodingKeys: String, CodingKey {
        case date
        case dateString
        case sgv
        case glucose
        case direction
        case id
        case type
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try container.encode(dateFormatter.string(from: date ?? Date()), forKey: .dateString)

        let dateAsUnixTimestamp = String(format: "%.0f", (date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000)
        try container.encode(dateAsUnixTimestamp, forKey: .date)

        try container.encode(direction, forKey: .direction)
        try container.encode(id, forKey: .id)

        // TODO: Handle the type of the glucose entry conditionally not hardcoded
        try container.encode("sgv", forKey: .type)

        if isManual {
            try container.encode(glucose, forKey: .glucose)
        } else {
            try container.encode(glucose, forKey: .sgv)
        }
    }
}
