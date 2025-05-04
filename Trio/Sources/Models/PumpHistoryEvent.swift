import Foundation
import LoopKit

struct PumpHistoryEvent: JSON, Equatable, Identifiable {
    let id: String
    let type: EventType
    let timestamp: Date
    let amount: Decimal?
    let duration: Int?
    let durationMin: Int?
    let rate: Decimal?
    let temp: TempType?
    let carbInput: Int?
    let fatInput: Int?
    let proteinInput: Int?
    let note: String?
    let isSMB: Bool?
    let isExternal: Bool?
    let isExternalInsulin: Bool?

    init(
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
        isExternalInsulin: Bool? = nil
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
    }
}

enum EventType: String, JSON {
    case bolus = "Bolus"
    case smb = "SMB"
    case isExternal = "External Insulin"
    case mealBolus = "Meal Bolus"
    case correctionBolus = "Correction Bolus"
    case snackBolus = "Snack Bolus"
    case bolusWizard = "BolusWizard"
    case tempBasal = "TempBasal"
    case tempBasalDuration = "TempBasalDuration"
    case pumpSuspend = "PumpSuspend"
    case pumpResume = "PumpResume"
    case pumpAlarm = "PumpAlarm"
    case pumpBattery = "PumpBattery"
    case rewind = "Rewind"
    case prime = "Prime"
    case journalCarbs = "JournalEntryMealMarker"

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

enum TempType: String, JSON {
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
    }
}

extension EventType {
    func mapEventTypeToPumpEventType() -> PumpEventType? {
        switch self {
        case .prime:
            return PumpEventType.prime
        case .pumpResume:
            return PumpEventType.resume
        case .rewind:
            return PumpEventType.rewind
        case .pumpSuspend:
            return PumpEventType.suspend
        case .nsBatteryChange,
             .pumpBattery:
            return PumpEventType.replaceComponent(componentType: .pump)
        case .nsInsulinChange:
            return PumpEventType.replaceComponent(componentType: .reservoir)
        case .nsSiteChange:
            return PumpEventType.replaceComponent(componentType: .infusionSet)
        case .pumpAlarm:
            return PumpEventType.alarm
        default:
            return nil
        }
    }
}
