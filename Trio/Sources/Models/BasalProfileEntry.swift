import Foundation

public struct BasalProfileEntry: JSON, Equatable {
    public let start: String
    public let minutes: Int
    public let rate: Decimal

    public init(start: String, minutes: Int, rate: Decimal) {
        self.start = start
        self.minutes = minutes
        self.rate = rate
    }
}

protocol BasalProfileObserver {
    func basalProfileDidChange(_ basalProfile: [BasalProfileEntry])
}

extension BasalProfileEntry {
    private enum CodingKeys: String, CodingKey {
        case start
        case minutes
        case rate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(String.self, forKey: .start)
        let minutes = try container.decode(Int.self, forKey: .minutes)
        let rate = try container.decode(Double.self, forKey: .rate).decimal ?? .zero

        self = BasalProfileEntry(start: start, minutes: minutes, rate: rate)
    }
}
