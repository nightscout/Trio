import Foundation

func determineBolusEventType(for event: PumpHistoryEvent) -> EventType {
    if event.isExternalInsulin ?? false {
        return .nsExternalInsulin
    } else if event.isSMB ?? false {
        return .SMB
    }
    return event.type
}

struct NightscoutTreatment: JSON, Hashable, Equatable {
    var duration: Int?
    var rawDuration: PumpHistoryEvent?
    var rawRate: PumpHistoryEvent?
    var absolute: Decimal?
    var rate: Decimal?
    var eventType: EventType
    var createdAt: Date?
    var enteredBy: String?
    var bolus: PumpHistoryEvent?
    var insulin: Decimal?
    var notes: String?
    var carbs: Decimal?
    var fat: Decimal?
    var protein: Decimal?
    var foodType: String?
    let targetTop: Decimal?
    let targetBottom: Decimal?

    static let local = "Trio"

    static let empty = NightscoutTreatment(from: "{}")!

    static func == (lhs: NightscoutTreatment, rhs: NightscoutTreatment) -> Bool {
        (lhs.createdAt ?? Date()) == (rhs.createdAt ?? Date())
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt ?? Date())
    }
}

extension NightscoutTreatment {
    private enum CodingKeys: String, CodingKey {
        case duration
        case rawDuration = "raw_duration"
        case rawRate = "raw_rate"
        case absolute
        case rate
        case eventType
        case createdAt = "created_at"
        case enteredBy
        case bolus
        case insulin
        case notes
        case carbs
        case fat
        case protein
        case foodType
        case targetTop
        case targetBottom
    }
}
