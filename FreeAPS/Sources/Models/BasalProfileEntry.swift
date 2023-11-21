import Foundation

struct BasalProfileEntry: JSON, Equatable, Identifiable {
    let id: String?
    let start: String
    let minutes: Int
    let rate: Decimal
}

protocol BasalProfileObserver {
    func basalProfileDidChange(_ basalProfile: [BasalProfileEntry])
}

extension BasalProfileEntry {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case start
        case minutes
        case rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let start = try container.decode(String.self, forKey: .start)
        let minutes = try container.decode(Int.self, forKey: .minutes)
        let rate = try container.decode(Double.self, forKey: .rate).decimal ?? .zero

        self = BasalProfileEntry(id: id, start: start, minutes: minutes, rate: rate)
    }
}
