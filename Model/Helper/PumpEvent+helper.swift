import CoreData
import Foundation

extension PumpEventStored {
    static func fetch(_ predicate: NSPredicate, ascending: Bool, fetchLimit: Int? = nil) -> NSFetchRequest<PumpEventStored> {
        let request = PumpEventStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: ascending)]
        request.resultType = .managedObjectResultType
        request.predicate = predicate
        if let fetchLimit = fetchLimit {
            request.fetchLimit = fetchLimit
        }
        return request
    }
}

public extension PumpEventStored {
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
    }

    enum TempType: String, JSON {
        case absolute
        case percent
    }
}

extension NSPredicate {
    static var pumpHistoryLast24h: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "timestamp >= %@", date as NSDate)
    }
}

// extension PumpEventStored: Encodable {
//    enum CodingKeys: String, CodingKey {
//        // pump event CD entitiy
//        case id
//        case timestamp
//        case type
//        // bolus CD entitity
//        case amount
//        case isSMB
//        case isExternal
//        // temp basal CD entity
//        case duration
//        case rate
//        case temp
//    }
//
//    public func encode(to encoder: Encoder) throws {
//        var containers = encoder.unkeyedContainer()
//
//        let dateFormatter = ISO8601DateFormatter()
//        let formattedDate = dateFormatter.string(from: timestamp ?? Date())
//
//        if let tempBasal = self.tempBasal {
//            // TempBasalDuration
//            var tempBasalDurationContainer = containers.nestedContainer(keyedBy: CodingKeys.self)
//            try tempBasalDurationContainer.encode("TempBasalDuration", forKey: .type)
//            try tempBasalDurationContainer.encode(tempBasal.duration, forKey: .duration)
//            try tempBasalDurationContainer.encode(formattedDate, forKey: .timestamp)
//            try tempBasalDurationContainer.encode(id ?? UUID().uuidString, forKey: .id)
//
//            // TempBasal
//            var tempBasalContainer = containers.nestedContainer(keyedBy: CodingKeys.self)
//            try tempBasalContainer.encode("TempBasal", forKey: .type)
//            if let rate = tempBasal.rate as Decimal? {
//                try tempBasalContainer.encode(rate, forKey: .rate)
//            } else {
//                try tempBasalContainer.encode(0, forKey: .rate)
//            }
//            // its called "temp" in the json thats passed into determineBasal hence the undescriptive name of this coding key
//            if let tempType = tempBasal.tempType {
//                try tempBasalContainer.encode(tempType, forKey: .temp)
//            } else {
//                try tempBasalContainer.encode("absolute", forKey: .temp)
//            }
//            try tempBasalContainer.encode(formattedDate, forKey: .timestamp)
//            // TempBasal and TempBasalDuration need to "relate" in the JSON, use same ID and prepemd with "_" here
//            try tempBasalContainer.encode("_\(id ?? UUID().uuidString)", forKey: .id)
//        }
//
//        // Encode specific to Bolus
//        if let bolus = self.bolus {
//            var bolusContainer = containers.nestedContainer(keyedBy: CodingKeys.self)
//            try bolusContainer.encode("Bolus", forKey: .type)
//            if let bolusAmount = bolus.amount as Decimal? {
//                try bolusContainer.encode(bolusAmount, forKey: .amount)
//            } else {
//                // Default value
//                try bolusContainer.encode(Decimal(0), forKey: .amount)
//            }
//            try bolusContainer.encode(bolus.isSMB, forKey: .isSMB)
//            try bolusContainer.encode(bolus.isExternal, forKey: .isExternal)
//            try bolusContainer.encode(formattedDate, forKey: .timestamp)
//            try bolusContainer.encode(id ?? UUID().uuidString, forKey: .id)
//        }
//    }
// }

// Declare helper structs ("data transfer objects" = DTO) to utilize parsing a flattened pump history
struct BolusDTO: Codable {
    var id: String
    var timestamp: String
    var amount: Double
    var isExternal: Bool
    var isSMB: Bool
    var duration: Int
    var _type: String = "Bolus"
}

struct TempBasalDTO: Codable {
    var id: String
    var timestamp: String
    var temp: String
    var rate: Double
    var _type: String = "TempBasal"
}

struct TempBasalDurationDTO: Codable {
    var id: String
    var timestamp: String
    var duration: Int
    var _type: String = "TempBasalDuration"

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case duration = "duration (min)"
        case _type
    }
}

// Mask distinct DTO subtypes with a common enum that conforms to Encodable
enum PumpEventDTO: Encodable {
    case bolus(BolusDTO)
    case tempBasal(TempBasalDTO)
    case tempBasalDuration(TempBasalDurationDTO)

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .bolus(bolus):
            try bolus.encode(to: encoder)
        case let .tempBasal(tempBasal):
            try tempBasal.encode(to: encoder)
        case let .tempBasalDuration(tempBasalDuration):
            try tempBasalDuration.encode(to: encoder)
        }
    }
}

// Extension with helper functions to map pump events to DTO objects via uniform masking enum
extension PumpEventStored {
    func toBolusDTOEnum() -> PumpEventDTO? {
        guard let id = id, let timestamp = timestamp, let bolus = bolus, let amount = bolus.amount else {
            return nil
        }
        let dateFormatter = ISO8601DateFormatter()
        let bolusDTO = BolusDTO(
            id: id,
            timestamp: dateFormatter.string(from: timestamp),
            amount: amount.doubleValue,
            isExternal: bolus.isExternal,
            isSMB: bolus.isSMB,
            duration: 0
        )
        return .bolus(bolusDTO)
    }

    func toTempBasalDTOEnum() -> PumpEventDTO? {
        guard let id = id, let timestamp = timestamp, let tempBasal = tempBasal, let rate = tempBasal.rate else {
            return nil
        }
        let dateFormatter = ISO8601DateFormatter()
        let tempBasalDTO = TempBasalDTO(
            id: "_\(id)",
            timestamp: dateFormatter.string(from: timestamp),
            temp: tempBasal.tempType ?? "unknown",
            rate: rate.doubleValue
        )
        return .tempBasal(tempBasalDTO)
    }

    func toTempBasalDurationDTOEnum() -> PumpEventDTO? {
        guard let id = id, let timestamp = timestamp, let tempBasal = tempBasal else {
            return nil
        }
        let dateFormatter = ISO8601DateFormatter()
        let tempBasalDurationDTO = TempBasalDurationDTO(
            id: id,
            timestamp: dateFormatter.string(from: timestamp),
            duration: Int(tempBasal.duration)
        )
        return .tempBasalDuration(tempBasalDurationDTO)
    }
}
