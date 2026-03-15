import Foundation

struct CarbRatios: JSON {
    let units: CarbUnit
    let schedule: [CarbRatioEntry]
}

struct CarbRatioEntry: JSON {
    let start: String
    let offset: Int
    let ratio: Decimal
}

enum CarbUnit: String, JSON {
    case grams
    case exchanges
}

extension CarbRatioEntry {
    private enum CodingKeys: String, CodingKey {
        case start
        case offset
        case ratio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(String.self, forKey: .start)
        let offset = try container.decode(Int.self, forKey: .offset)
        let ratio = try container.decode(Double.self, forKey: .ratio).decimal ?? .zero

        self = CarbRatioEntry(start: start, offset: offset, ratio: ratio)
    }
}
