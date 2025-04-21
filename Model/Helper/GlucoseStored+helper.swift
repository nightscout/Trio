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
        guard glucose.count >= 6 else { return false }

        let firstValue = glucose.first?.glucose

        return glucose.allSatisfy { $0.glucose == firstValue }
    }

    // Preview
    @discardableResult static func makePreviewGlucose(count: Int, provider: CoreDataStack) -> [GlucoseStored] {
        let context = provider.persistentContainer.viewContext
        let baseGlucose = 120
        let glucoseValues = (0 ..< count).map { index -> GlucoseStored in
            let glucose = GlucoseStored(context: context)
            glucose.id = UUID()
            glucose.date = Date.now.addingTimeInterval(Double(index) * -300) // Every 5 minutes
            glucose.glucose = Int16(baseGlucose + (index % 3) * 10) // Varying between 120-140
            glucose.direction = BloodGlucose.Direction.flat.rawValue
            glucose.isManual = false
            glucose.isUploadedToNS = false
            glucose.isUploadedToHealth = false
            glucose.isUploadedToTidepool = false
            return glucose
        }

        try? context.save()
        return glucoseValues
    }
}

extension NSPredicate {
    static var glucose: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
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

    static var glucoseNotYetUploadedToNightscout: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "date >= %@ AND isUploadedToNS == %@", date as NSDate, false as NSNumber)
    }

    static var glucoseNotYetUploadedToHealth: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "date >= %@ AND isUploadedToHealth == %@", date as NSDate, false as NSNumber)
    }

    static var glucoseNotYetUploadedToTidepool: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "date >= %@ AND isUploadedToTidepool == %@", date as NSDate, false as NSNumber)
    }

    static var manualGlucoseNotYetUploadedToNightscout: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToNS == %@ AND isManual == %@",
            date as NSDate,
            false as NSNumber,
            true as NSNumber
        )
    }

    static var manualGlucoseNotYetUploadedToHealth: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToHealth == %@ AND isManual == %@",
            date as NSDate,
            false as NSNumber,
            true as NSNumber
        )
    }

    static var manualGlucoseNotYetUploadedToTidepool: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND isUploadedToTidepool == %@ AND isManual == %@",
            date as NSDate,
            false as NSNumber,
            true as NSNumber
        )
    }
}

struct GlucoseEntryDTO: Decodable, ImportableDTO {
    var id: UUID?
    var date: Date?
    var glucose: Int
    var direction: String?
    var isManual: Bool?

    // Custom initializer to handle numeric dates
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)
        glucose = try container.decode(Int.self, forKey: .glucose)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? false

        // Handle numeric date
        if let timestamp = try? container.decode(Double.self, forKey: .date) {
            // Assuming the timestamp is in milliseconds
            date = Date(timeIntervalSince1970: timestamp / 1000)
        } else {
            date = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case glucose
        case direction
        case isManual
    }

    // Conformance to ImportableDTO
    typealias ManagedObject = GlucoseStored

    func store(in context: NSManagedObjectContext) -> GlucoseStored {
        let glucoseEntry = GlucoseStored(context: context)
        glucoseEntry.id = id ?? UUID()
        glucoseEntry.date = date ?? Date()
        glucoseEntry.glucose = Int16(glucose)
        glucoseEntry.direction = direction
        glucoseEntry.isManual = isManual ?? false
        glucoseEntry.isUploadedToNS = true
        glucoseEntry.isUploadedToHealth = true
        glucoseEntry.isUploadedToTidepool = true

        return glucoseEntry
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

// In order to show the correct direction in the bobble we convert the direction property of the NSManagedObject GlucoseStored back to the Direction type
extension GlucoseStored {
    var directionEnum: BloodGlucose.Direction? {
        BloodGlucose.Direction(rawValue: direction ?? "")
    }
}
