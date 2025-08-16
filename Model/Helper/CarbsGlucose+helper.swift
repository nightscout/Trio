import Foundation

struct CarbAndGlucose: Encodable {
    let carbs: Decimal
    let glucose: Decimal

    enum CodingKeys: String, CodingKey {
        case carbs
        case glucose
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(NSDecimalNumber(decimal: carbs).stringValue, forKey: .carbs)
        try container.encode(NSDecimalNumber(decimal: glucose).stringValue, forKey: .glucose)
    }
}
