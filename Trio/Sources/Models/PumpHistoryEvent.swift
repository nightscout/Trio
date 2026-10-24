import Foundation

public struct PumpHistoryEvent: JSON, Equatable, Identifiable {
    public let id: String
    public let type: EventType
    public let timestamp: Date
    public let amount: Decimal?
    public let duration: Int?
    public let durationMin: Int?
    public let rate: Decimal?
    public let temp: TempType?
    public let carbInput: Int?
    public let fatInput: Int?
    public let proteinInput: Int?
    public let note: String?
    public let isSMB: Bool?
    public let isExternal: Bool?
    public let isExternalInsulin: Bool?
    public let isScheduledBasal: Bool?
    public let deliveredUnits: Decimal?
    public let programmedAmount: Decimal?
    public let insulinType: String?

    public init(
        id: String,
        type: EventType,
        timestamp: Date,
        amount: Decimal? = nil,
        duration: Int? = nil,
        durationMin: Int? = nil,
        rate: Decimal? = nil,
        temp: TempType? = nil,
        carbInput: Int? = nil,
        fatInput: Int? = nil,
        proteinInput: Int? = nil,
        note: String? = nil,
        isSMB: Bool? = nil,
        isExternal: Bool? = nil,
        isExternalInsulin: Bool? = nil,
        isScheduledBasal: Bool? = nil,
        deliveredUnits: Decimal? = nil,
        programmedAmount: Decimal? = nil,
        insulinType: String? = nil
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
        self.isExternalInsulin = isExternalInsulin
        self.isScheduledBasal = isScheduledBasal
        self.deliveredUnits = deliveredUnits
        self.programmedAmount = programmedAmount
        self.insulinType = insulinType
    }
}

public enum EventType: String, JSON {
    case bolus = "Bolus"
    case smb = "SMB"
    case isExternal = "External Insulin"
    case tempBasal = "TempBasal"
    case tempBasalDuration = "TempBasalDuration"
    case pumpSuspend = "PumpSuspend"
    case pumpResume = "PumpResume"
    case pumpAlarm = "PumpAlarm"
    case pumpBattery = "PumpBattery"
    case rewind = "Rewind"
    case prime = "Prime"

    case nsTempBasal = "Temp Basal"
    case nsCarbCorrection = "Carb Correction"
    case nsTempTarget = "Temporary Target"
    case nsInsulinChange = "Insulin Change"
    case nsSiteChange = "Site Change"
    case nsBatteryChange = "Pump Battery Change"
    case nsAnnouncement = "Announcement"
    case nsSensorChange = "Sensor Start"
    case capillaryGlucose = "BG Check"
    case note = "Note"
}

public enum TempType: String, JSON {
    case absolute
    case percent
}

extension PumpHistoryEvent {
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
        case isExternalInsulin
        case isScheduledBasal
        case deliveredUnits
        case programmedAmount
        case insulinType
    }
}
