import Foundation

struct TDD: Sendable, Codable, Equatable, Identifiable {
    var id = UUID()

    let totalDailyDose: Decimal?
    let timestamp: Date?

    init(totalDailyDose: Decimal?, timestamp: Date?) {
        self.totalDailyDose = totalDailyDose
        self.timestamp = timestamp
    }

    init?(from dictionary: [String: Any]) {
        guard let deliverAt = dictionary["deliverAt"] as? Date,
              let totalDailyDose = dictionary["totalDailyDose"] as? Decimal
        else {
            return nil
        }

        self.totalDailyDose = totalDailyDose
        timestamp = deliverAt
    }
}
