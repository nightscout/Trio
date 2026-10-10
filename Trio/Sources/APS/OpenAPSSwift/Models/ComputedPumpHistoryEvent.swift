import Foundation

public struct ComputedPumpHistoryEvent: Codable, Equatable, Identifiable {
    public let id: String
    public let type: EventType
    public let timestamp: Date
    public let amount: Decimal?
    public var duration: Decimal?
    public let durationMin: Int?
    public let rate: Decimal?
    public let temp: TempType?
    public let carbInput: Int?
    public let fatInput: Int?
    public let proteinInput: Int?
    public let note: String?
    public let isSMB: Bool?
    public let isExternal: Bool?
    public let insulin: Decimal?
    public let isTempBolus: Bool
    public let omitFromTempHistory: Bool

    // Make these non-computed properties to ensure they're always set
    public let started_at: Date
    public let date: UInt64

    public var end: Date {
        timestamp + (duration ?? durationMin.map { Decimal($0) } ?? 0).minutesToSeconds
    }

    public init(
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
