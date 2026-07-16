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

    // Preview
    @discardableResult static func makePreviewEvents(count: Int, provider: CoreDataStack) -> [PumpEventStored] {
        let context = provider.persistentContainer.viewContext
        let events = (0 ..< count).map { index -> PumpEventStored in
            let event = PumpEventStored(context: context)
            event.id = UUID().uuidString
            event.timestamp = Date.now.addingTimeInterval(Double(index) * -300) // Every 5 minutes
            event.type = EventType.bolus.rawValue
            event.isUploadedToNS = false
            event.isUploadedToHealth = false
            event.isUploadedToTidepool = false

            // Add a bolus
            let bolus = BolusStored(context: context)
            bolus.amount = 2.5 as NSDecimalNumber
            bolus.isExternal = false
            bolus.isSMB = false
            bolus.pumpEvent = event

            return event
        }

        try? context.save()
        return events
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
        case siteChange = "SiteChange"

        case nsNote = "Note"
        case nsTempBasal = "Temp Basal"
        case nsCarbCorrection = "Carb Correction"
        case nsTempTarget = "Temporary Target"
        case nsInsulinChange = "Insulin Change"
        case nsSiteChange = "Site Change"
        case nsBatteryChange = "Pump Battery Change"
        case nsAnnouncement = "Announcement"
        case nsSensorChange = "Sensor Start"
        case nsExercise = "Exercise"
        case capillaryGlucose = "BG Check"
    }

    enum TempType: String, JSON {
        case absolute
        case percent
    }
}

extension NSPredicate {
    static var pumpHistoryLast1440Minutes: NSPredicate {
        let date = Date.oneDayAgoInMinutes
        return NSPredicate(format: "timestamp >= %@", date as NSDate)
    }

    static var pumpHistoryLast48h: NSPredicate {
        let date = Date() - TimeInterval(hours: 48)
        return NSPredicate(format: "timestamp >= %@", date as NSDate)
    }

    static var pumpHistoryLast24h: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "timestamp >= %@", date as NSDate)
    }

    static func pumpHistory(since date: Date) -> NSPredicate {
        NSPredicate(format: "timestamp >= %@", date as NSDate)
    }

    static var pumpHistoryForStats: NSPredicate {
        let date = Date.threeMonthsAgo
        return NSPredicate(format: "pumpEvent.timestamp >= %@", date as NSDate)
    }

    static var recentPumpHistory: NSPredicate {
        let date = Date.twentyMinutesAgo
        return NSPredicate(
            format: "type == %@ AND timestamp >= %@",
            PumpEventStored.EventType.tempBasal.rawValue,
            date as NSDate
        )
    }

    static var lastPumpBolus: NSPredicate {
        let date = Date.twentyMinutesAgo
        return NSPredicate(format: "timestamp >= %@ AND bolus.isExternal == %@", date as NSDate, false as NSNumber)
    }

    static func duplicates(_ date: Date) -> NSPredicate {
        NSPredicate(format: "timestamp == %@", date as NSDate)
    }

    static var pumpEventsNotYetUploadedToNightscout: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "timestamp >= %@ AND isUploadedToNS == %@", date as NSDate, false as NSNumber)
    }

    static var pumpEventsNotYetUploadedToHealth: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "timestamp >= %@ AND isUploadedToHealth == %@", date as NSDate, false as NSNumber)
    }

    static var pumpEventsNotYetUploadedToTidepool: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "timestamp >= %@ AND isUploadedToTidepool == %@", date as NSDate, false as NSNumber)
    }
}

// MARK: - Native mapping

extension PumpEventStored {
    /// Converts a stored pump event into the `PumpHistoryEvent`s the oref algorithm can use.
    /// A temp basal yields a duration entry followed by a rate entry.
    func toPumpHistoryEvents() -> [PumpHistoryEvent] {
        var events: [PumpHistoryEvent] = []
        if let bolus = toBolusPumpHistoryEvent() { events.append(bolus) }
        if let duration = toTempBasalDurationPumpHistoryEvent() { events.append(duration) }
        if let tempBasal = toTempBasalPumpHistoryEvent() { events.append(tempBasal) }
        if let suspend = toSuspendPumpHistoryEvent() { events.append(suspend) }
        if let resume = toResumePumpHistoryEvent() { events.append(resume) }
        if let rewind = toRewindPumpHistoryEvent() { events.append(rewind) }
        if let prime = toPrimePumpHistoryEvent() { events.append(prime) }
        return events
    }

    private func toBolusPumpHistoryEvent() -> PumpHistoryEvent? {
        guard let timestamp = timestamp, let bolus = bolus, let amount = bolus.amount else {
            return nil
        }
        return PumpHistoryEvent(
            id: id ?? UUID().uuidString,
            type: .bolus,
            timestamp: timestamp,
            amount: Decimal(algorithmValue: amount.doubleValue),
            duration: 0,
            isSMB: bolus.isSMB,
            isExternal: bolus.isExternal
        )
    }

    // The temp basal duration populates `durationMin`, not `duration`.
    private func toTempBasalDurationPumpHistoryEvent() -> PumpHistoryEvent? {
        guard let id = id, let timestamp = timestamp, let tempBasal = tempBasal else {
            return nil
        }
        return PumpHistoryEvent(
            id: id,
            type: .tempBasalDuration,
            timestamp: timestamp,
            durationMin: Int(tempBasal.duration)
        )
    }

    // The temp basal rate entry id is prefixed with "_". An unrecognized `tempType` maps to nil.
    private func toTempBasalPumpHistoryEvent() -> PumpHistoryEvent? {
        guard let id = id, let timestamp = timestamp, let tempBasal = tempBasal, let rate = tempBasal.rate else {
            return nil
        }
        return PumpHistoryEvent(
            id: "_\(id)",
            type: .tempBasal,
            timestamp: timestamp,
            rate: Decimal(algorithmValue: rate.doubleValue),
            temp: tempBasal.tempType.flatMap { Trio.TempType(rawValue: $0) }
        )
    }

    private func toSuspendPumpHistoryEvent() -> PumpHistoryEvent? {
        guard let id = id, let timestamp = timestamp, type == EventType.pumpSuspend.rawValue else {
            return nil
        }
        return PumpHistoryEvent(id: id, type: .pumpSuspend, timestamp: timestamp)
    }

    private func toResumePumpHistoryEvent() -> PumpHistoryEvent? {
        guard let id = id, let timestamp = timestamp, type == EventType.pumpResume.rawValue else {
            return nil
        }
        return PumpHistoryEvent(id: id, type: .pumpResume, timestamp: timestamp)
    }

    private func toRewindPumpHistoryEvent() -> PumpHistoryEvent? {
        guard let id = id, let timestamp = timestamp, type == EventType.rewind.rawValue else {
            return nil
        }
        return PumpHistoryEvent(id: id, type: .rewind, timestamp: timestamp)
    }

    private func toPrimePumpHistoryEvent() -> PumpHistoryEvent? {
        guard let id = id, let timestamp = timestamp, type == EventType.prime.rawValue else {
            return nil
        }
        return PumpHistoryEvent(id: id, type: .prime, timestamp: timestamp)
    }
}
