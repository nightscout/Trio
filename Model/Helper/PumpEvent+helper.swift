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

extension PumpEventStored: Encodable {
    enum CodingKeys: String, CodingKey {
        // pump event CD entitiy
        case id
        case timestamp
        case type
        // bolus CD entitity
        case amount
        case isSMB
        case isExternal
        // temp basal CD entity
        case duration
        case rate
        case tempType
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let dateFormatter = ISO8601DateFormatter()
        let formattedDate = dateFormatter.string(from: timestamp ?? Date())

        // PumpEventStored
        try container.encode(id, forKey: .id)
        try container.encode(formattedDate, forKey: .timestamp)
        try container.encode(type, forKey: .type)

        // access to BolusStored entity
        //
        // amount
        if let bolusAmount = bolus?.amount as Decimal? {
            try container.encode(bolusAmount, forKey: .amount)
        } else {
            // Default value
            try container.encode(Decimal(0), forKey: .amount)
        }
        // isSMB
        if let isSMB = bolus?.isSMB {
            try container.encode(isSMB, forKey: .isSMB)
        } else {
            try container.encode(true, forKey: .amount)
        }
        // isExternal
        if let isExternal = bolus?.isExternal {
            try container.encode(isExternal, forKey: .isExternal)
        } else {
            try container.encode(false, forKey: .isExternal)
        }

        // access to TempBasalStored entity
        //
        // duration
        if let duration = tempBasal?.duration {
            try container.encode(duration, forKey: .duration)
        } else {
            try container.encode(0, forKey: .duration)
        }
        // rate
        if let rate = tempBasal?.rate as Decimal? {
            try container.encode(rate, forKey: .rate)
        } else {
            try container.encode(0, forKey: .rate)
        }
        // temp type
        if let tempType = tempBasal?.tempType {
            try container.encode(tempType, forKey: .tempType)
        } else {
            try container.encode("absolute", forKey: .tempType)
        }
    }
}
