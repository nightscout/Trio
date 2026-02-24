import Foundation

/// Helper class so that we can have a plain Swift object to serialize GlucoseStorage
struct AlgorithmGlucose: Codable {
    var date: Date?
    var direction: String?
    var glucose: Int16
    var id: UUID?
    var isManual: Bool

    enum CodingKeys: String, CodingKey {
        case date
        case dateString
        case sgv
        case glucose
        case direction
        case id
        case type
    }

    init(date: Date?, direction: String?, glucose: Int16, id: UUID?, isManual: Bool) {
        self.date = date
        self.direction = direction
        self.glucose = glucose
        self.id = id
        self.isManual = isManual
    }

    // this constructor is just for testing
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let dateString = try container.decodeIfPresent(String.self, forKey: .dateString) {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = dateFormatter.date(from: dateString)
        } else if let dateStringTimestamp = try container.decodeIfPresent(String.self, forKey: .date),
                  let dateTimestamp = TimeInterval(dateStringTimestamp)
        {
            date = Date(timeIntervalSince1970: dateTimestamp / 1000)
        } else {
            date = nil
        }

        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)

        if let glucoseValue = try container.decodeIfPresent(Int16.self, forKey: .glucose) {
            glucose = glucoseValue
            isManual = true
        } else if let sgvValue = try container.decodeIfPresent(Int16.self, forKey: .sgv) {
            glucose = sgvValue
            isManual = false
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .sgv,
                in: container,
                debugDescription: "Neither 'glucose' nor 'sgv' key found or value is not Int16"
            )
        }
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
