import Foundation

struct ComputedPumpHistoryEvent: Codable, Equatable, Identifiable {
    let id: String
    let type: EventType
    let timestamp: Date
    let amount: Decimal?
    var duration: Decimal?
    let durationMin: Int?
    let rate: Decimal?
    let temp: TempType?
    let carbInput: Int?
    let fatInput: Int?
    let proteinInput: Int?
    let note: String?
    let isSMB: Bool?
    let isExternal: Bool?
    let insulin: Decimal?
    let isTempBolus: Bool
    let omitFromTempHistory: Bool

    // Make these non-computed properties to ensure they're always set
    let started_at: Date
    let date: UInt64

    var end: Date {
        timestamp + (duration ?? durationMin.map { Decimal($0) } ?? 0).minutesToSeconds
    }

    init(
        id: String,
        type: EventType,
        timestamp: Date,
        amount: Decimal?,
        duration: Decimal?,
        durationMin: Int?,
        rate: Decimal?,
        temp: TempType?,
        carbInput: Int?,
        fatInput: Int?,
        proteinInput: Int?,
        note: String?,
        isSMB: Bool?,
        isExternal: Bool?,
        insulin: Decimal?,
        isTempBolus: Bool = false,
        omitFromTempHistory: Bool = false
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.amount = amount
        self.duration = duration
        self.durationMin = durationMin
        self.rate = rate
        self.temp = temp
        self.carbInput = carbInput
        self.fatInput = fatInput
        self.proteinInput = proteinInput
        self.note = note
        self.isSMB = isSMB
        self.isExternal = isExternal
        self.insulin = insulin
        self.isTempBolus = isTempBolus
        self.omitFromTempHistory = omitFromTempHistory

        // Explicitly set started_at and date as required by history.js
        started_at = timestamp // This matches behavior of new Date(tz(timestamp))
        date = UInt64(timestamp.timeIntervalSince1970 * 1000) // This matches behavior of started_at.getTime()
    }
}

extension ComputedPumpHistoryEvent {
    private enum CodingKeys: String, CodingKey {
        case id
        case type = "_type"
        case timestamp
        case amount
        case duration
        case durationMin = "duration (min)"
        case rate
        case temp
        case carbInput = "carb_input"
        case fatInput
        case proteinInput
        case note
        case isSMB
        case isExternal
        case started_at
        case date
        case insulin
        case isTempBolus
        case omitFromTempHistory
    }
}
