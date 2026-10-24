import Foundation

protocol CarbRatiosObserver {
    func carbRatiosDidChange(_ carbRatios: CarbRatios)
}

public struct CarbRatios: JSON {
    public let units: CarbUnit
    public let schedule: [CarbRatioEntry]

    public init(units: CarbUnit, schedule: [CarbRatioEntry]) {
        self.units = units
        self.schedule = schedule
    }
}

public struct CarbRatioEntry: JSON {
    public let start: String
    public let offset: Int
    public let ratio: Decimal

    public init(start: String, offset: Int, ratio: Decimal) {
        self.start = start
        self.offset = offset
        self.ratio = ratio
    }
}

public enum CarbUnit: String, JSON {
    case grams
    case exchanges
}

extension CarbRatioEntry {
    private enum CodingKeys: String, CodingKey {
        case start
        case offset
        case ratio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(String.self, forKey: .start)
        let offset = try container.decode(Int.self, forKey: .offset)
        let ratio = try container.decode(Double.self, forKey: .ratio).decimal ?? .zero

        self = CarbRatioEntry(start: start, offset: offset, ratio: ratio)
    }
}
