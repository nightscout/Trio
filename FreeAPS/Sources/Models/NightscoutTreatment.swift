import Foundation

func determineBolusEventType(for event: PumpHistoryEvent) -> EventType {
    if event.isExternalInsulin ?? false {
        return .nsExternalInsulin
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

    static let local = "Open-iAPS"

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

    init?(event: PumpHistoryEvent, tempBasalDuration: PumpHistoryEvent? = nil) {
        var basalDurationEvent: PumpHistoryEvent?
        if tempBasalDuration != nil, tempBasalDuration?.timestamp == event.timestamp, event.type == .tempBasal,
           tempBasalDuration?.type == .tempBasalDuration
        {
            basalDurationEvent = tempBasalDuration
        }
        switch event.type {
        case .tempBasal:
            self.init(
                duration: basalDurationEvent?.durationMin,
                rawDuration: basalDurationEvent,
                rawRate: event,
                absolute: event.rate,
                rate: event.rate,
                eventType: .nsTempBasal,
                createdAt: event.timestamp,
                enteredBy: NightscoutTreatment.local,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
        case .bolus:
            let eventType = determineBolusEventType(for: event)
            self.init(
                duration: event.duration,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: eventType,
                createdAt: event.timestamp,
                enteredBy: NightscoutTreatment.local,
                bolus: event,
                insulin: event.amount,
                notes: nil,
                carbs: nil,
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
        case .journalCarbs:
            self.init(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsCarbCorrection,
                createdAt: event.timestamp,
                enteredBy: NightscoutTreatment.local,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: Decimal(event.carbInput ?? 0),
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
        case .prime:
            self.init(
                duration: event.duration,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsSiteChange,
                createdAt: event.timestamp,
                enteredBy: NightscoutTreatment.local,
                bolus: event,
                insulin: nil,
                notes: nil,
                carbs: nil,
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
        case .rewind:
            self.init(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsInsulinChange,
                createdAt: event.timestamp,
                enteredBy: NightscoutTreatment.local,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
        case .pumpAlarm:
            self.init(
                duration: 30, // minutes
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsAnnouncement,
                createdAt: event.timestamp,
                enteredBy: NightscoutTreatment.local,
                bolus: nil,
                insulin: nil,
                notes: "Alarm \(String(describing: event.note)) \(event.type)",
                carbs: nil,
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
        default:
            return nil
        }
    }
}
