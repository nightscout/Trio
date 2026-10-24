import Foundation

protocol InsulinSensitivitiesObserver {
    func insulinSensitivitiesDidChange(_ sensitivities: InsulinSensitivities)
}

public struct InsulinSensitivities: JSON {
    public var units: GlucoseUnits
    public var userPreferredUnits: GlucoseUnits
    public var sensitivities: [InsulinSensitivityEntry]

    public init(units: GlucoseUnits, userPreferredUnits: GlucoseUnits, sensitivities: [InsulinSensitivityEntry]) {
        self.units = units
        self.userPreferredUnits = userPreferredUnits
        self.sensitivities = sensitivities
    }
}

extension InsulinSensitivities {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case sensitivities
    }
}

public struct InsulinSensitivityEntry: JSON {
    public let sensitivity: Decimal
    public let offset: Int
    public let start: String

    public init(sensitivity: Decimal, offset: Int, start: String) {
        self.sensitivity = sensitivity
        self.offset = offset
        self.start = start
    }
}

extension InsulinSensitivityEntry {
    private enum CodingKeys: String, CodingKey {
        case sensitivity
        case offset
        case start
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sensitivity = try container.decode(Double.self, forKey: .sensitivity).decimal ?? .zero
        let start = try container.decode(String.self, forKey: .start)
        let offset = try container.decode(Int.self, forKey: .offset)

        self = InsulinSensitivityEntry(sensitivity: sensitivity, offset: offset, start: start)
    }
}
