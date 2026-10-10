import Foundation

public struct ComputedInsulinSensitivities: Codable {
    public let units: GlucoseUnits
    public let userPreferredUnits: GlucoseUnits
    public let sensitivities: [ComputedInsulinSensitivityEntry]

    public init(
        units: GlucoseUnits,
        userPreferredUnits: GlucoseUnits,
        sensitivities: [ComputedInsulinSensitivityEntry]
    ) {
        self.units = units
        self.userPreferredUnits = userPreferredUnits
        self.sensitivities = sensitivities
    }

    func toInsulinSensitivities() -> InsulinSensitivities {
        let sensitivities = self.sensitivities
            .map { InsulinSensitivityEntry(sensitivity: $0.sensitivity, offset: $0.offset, start: $0.start) }
        return InsulinSensitivities(units: units, userPreferredUnits: userPreferredUnits, sensitivities: sensitivities)
    }
}

extension ComputedInsulinSensitivities {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case sensitivities
    }
}

public struct ComputedInsulinSensitivityEntry: Codable {
    public let sensitivity: Decimal
    public let offset: Int
    public let start: String
    public var endOffset: Int?
    public let id: UUID // we use this to help with mutating inputs, we don't serialize it

    public init(sensitivity: Decimal, offset: Int, start: String, endOffset: Int? = nil, id: UUID? = nil) {
        self.sensitivity = sensitivity
        self.offset = offset
        self.start = start
        self.endOffset = endOffset
        self.id = id ?? UUID()
    }

    enum CodingKeys: CodingKey {
        case sensitivity
        case offset
        case start
        case endOffset
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sensitivity, forKey: .sensitivity)
        try container.encode(offset, forKey: .offset)
        try container.encode(start, forKey: .start)
        try container.encodeIfPresent(endOffset, forKey: .endOffset)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sensitivity = try container.decode(Decimal.self, forKey: .sensitivity)
        offset = try container.decode(Int.self, forKey: .offset)
        start = try container.decode(String.self, forKey: .start)
        endOffset = try container.decodeIfPresent(Int.self, forKey: .endOffset)
        id = UUID()
    }
}
