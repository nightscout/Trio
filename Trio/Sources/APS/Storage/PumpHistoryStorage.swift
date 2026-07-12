import Combine
import CoreData
import Foundation
import LoopKit
import SwiftDate
import Swinject

protocol PumpHistoryObserver {
    func pumpHistoryDidUpdate(_ events: [PumpHistoryEvent])
}

protocol PumpHistoryStorage {
    var updatePublisher: AnyPublisher<Void, Never> { get }
    func getPumpHistory() async throws -> [PumpHistoryEvent]
    func storePumpEvents(_ events: [NewPumpEvent]) async throws
    func storeExternalInsulinEvent(amount: Decimal, timestamp: Date) async
    func getPumpHistoryNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getPumpHistoryNotYetUploadedToHealth() async throws -> [PumpHistoryEvent]
    func getPumpHistoryNotYetUploadedToTidepool() async throws -> [PumpHistoryEvent]
}

final class BasePumpHistoryStorage: PumpHistoryStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BasePumpHistoryStorage.processQueue")
    @Injected() var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    let updateSubject = PassthroughSubject<Void, Never>()

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    let context: NSManagedObjectContext

    init(resolver: Resolver, context: NSManagedObjectContext? = nil) {
        self.context = context ?? CoreDataStack.shared.newTaskContext()
        injectServices(resolver)
    }

    typealias PumpEvent = PumpEventStored.EventType
    typealias TempType = PumpEventStored.TempType

    private func roundDose(_ dose: Double, toIncrement increment: Double) -> Decimal {
        let roundedValue = (dose / increment).rounded() * increment
        return Decimal(roundedValue)
    }

    func storePumpEvents(_ events: [NewPumpEvent]) async throws {
        try await context.perform {
            // upsert candidates: dose syncIdentifier, timestamp+type as fallback
            let syncIdentifiers = events.compactMap(\.dose?.syncIdentifier)
            let timestamps = events.map(\.date)
            let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "syncIdentifier IN %@", syncIdentifiers),
                NSPredicate(format: "timestamp IN %@", timestamps)
            ])
            let existingRows = try self.context.fetch(request)

            var bySyncIdentifier = Dictionary(
                existingRows.compactMap { row in row.syncIdentifier.map { ($0, row) } },
                uniquingKeysWith: { first, _ in first }
            )
            var byTimestampAndType = Dictionary(
                existingRows.map { (TimestampAndType(timestamp: $0.timestamp ?? .distantPast, type: $0.type ?? ""), $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for event in events {
                guard let storedType = event.type?.storedEventType else { continue }

                // type-aware key: same-timestamp bolus + TBR no longer shadow each other
                let fallbackKey = TimestampAndType(timestamp: event.date, type: storedType.rawValue)
                let match = event.dose?.syncIdentifier.flatMap { bySyncIdentifier[$0] }
                    ?? byTimestampAndType[fallbackKey]

                if let match = match {
                    // finalized rows never change
                    if match.isMutable, let dose = event.dose {
                        self.updateMutablePumpEvent(match, with: dose)
                    }
                    continue
                }

                let newPumpEvent = PumpEventStored(context: self.context)
                newPumpEvent.id = UUID().uuidString
                // restrict entry to now or past
                newPumpEvent.timestamp = min(event.date, Date())
                newPumpEvent.type = storedType.rawValue
                newPumpEvent.syncIdentifier = event.dose?.syncIdentifier
                newPumpEvent.isMutable = event.dose?.isMutable ?? false
                newPumpEvent.isUploadedToNS = false
                newPumpEvent.isUploadedToHealth = false
                newPumpEvent.isUploadedToTidepool = false

                switch storedType {
                case .bolus:
                    guard let dose = event.dose else {
                        self.context.delete(newPumpEvent)
                        continue
                    }
                    let newBolusEntry = BolusStored(context: self.context)
                    newBolusEntry.pumpEvent = newPumpEvent
                    newBolusEntry.amount = NSDecimalNumber(decimal: self.roundDose(
                        dose.unitsInDeliverableIncrements,
                        toIncrement: Double(self.settings.preferences.bolusIncrement)
                    ))
                    newBolusEntry.isExternal = dose.manuallyEntered
                    newBolusEntry.isSMB = dose.automatic ?? true

                case .tempBasal:
                    guard let dose = event.dose else {
                        self.context.delete(newPumpEvent)
                        continue
                    }
                    let newTempBasal = TempBasalStored(context: self.context)
                    newTempBasal.pumpEvent = newPumpEvent
                    newTempBasal.duration = Int16(round((dose.endDate - dose.startDate).timeInterval / 60))
                    newTempBasal.rate = Decimal(dose.unitsPerHour) as NSDecimalNumber
                    newTempBasal.startDate = dose.startDate
                    newTempBasal.endDate = dose.endDate
                    newTempBasal.deliveredUnits = dose.deliveredUnits.map { Decimal($0) as NSDecimalNumber }
                    newTempBasal.tempType = TempType.absolute.rawValue
                    newTempBasal.isScheduledBasal = event.type == .basal

                case .pumpAlarm:
                    newPumpEvent.note = event.title

                default:
                    break
                }

                // same-batch dedup
                if let syncIdentifier = newPumpEvent.syncIdentifier {
                    bySyncIdentifier[syncIdentifier] = newPumpEvent
                }
                byTimestampAndType[fallbackKey] = newPumpEvent
            }

            do {
                guard self.context.hasChanges else { return }
                try self.context.save()

                self.updateSubject.send(())
                debug(.coreData, "\(DebuggingIdentifiers.succeeded) stored pump events in Core Data")
            } catch let error as NSError {
                debug(.coreData, "\(DebuggingIdentifiers.failed) failed to store pump events with error: \(error.userInfo)")
                throw error
            }
        }
    }

    /// Finalized reports freeze the row with delivered values. Upload flags
    /// untouched: blind re-POSTs would duplicate NS treatments.
    private func updateMutablePumpEvent(_ event: PumpEventStored, with dose: DoseEntry) {
        switch event.type {
        case PumpEventStored.EventType.bolus.rawValue:
            guard let bolus = event.bolus else { return }
            let finalAmount = dose.deliveredUnits.map {
                self.roundDose($0, toIncrement: Double(settings.preferences.bolusIncrement))
            }
            if let finalAmount = finalAmount {
                bolus.amount = finalAmount as NSDecimalNumber
            }
            bolus.isSMB = dose.automatic ?? true
            event.isMutable = dose.isMutable
            if !dose.isMutable {
                debug(.coreData, "Finalized bolus \(dose.syncIdentifier ?? "-"): \(bolus.amount ?? 0) U")
            }

        case PumpEventStored.EventType.tempBasal.rawValue:
            guard let tempBasal = event.tempBasal else { return }
            tempBasal.duration = Int16(round((dose.endDate - dose.startDate).timeInterval / 60))
            tempBasal.rate = Decimal(dose.unitsPerHour) as NSDecimalNumber
            tempBasal.startDate = dose.startDate
            tempBasal.endDate = dose.endDate
            tempBasal.deliveredUnits = dose.deliveredUnits.map { Decimal($0) as NSDecimalNumber }
            event.isMutable = dose.isMutable
            if !dose.isMutable {
                debug(
                    .coreData,
                    "Finalized temp basal \(dose.syncIdentifier ?? "-"): \(tempBasal.rate ?? 0) U/hr, \(tempBasal.duration) min"
                )
            }

        default:
            // non-dose rows have no revisable payload
            event.isMutable = dose.isMutable
        }
    }

    func storeExternalInsulinEvent(amount: Decimal, timestamp: Date) async {
        await context.perform {
            // create pump event
            let newPumpEvent = PumpEventStored(context: self.context)
            let identifier = UUID().uuidString
            newPumpEvent.id = identifier
            // Trio-created record: it is its own source of truth, born final.
            newPumpEvent.syncIdentifier = identifier
            newPumpEvent.isMutable = false
            // restrict entry to now or past
            newPumpEvent.timestamp = timestamp > Date() ? Date() : timestamp
            newPumpEvent.type = PumpEvent.bolus.rawValue
            newPumpEvent.isUploadedToNS = false
            newPumpEvent.isUploadedToHealth = false
            newPumpEvent.isUploadedToTidepool = false

            // create bolus entry and specify relationship to pump event
            let newBolusEntry = BolusStored(context: self.context)
            newBolusEntry.pumpEvent = newPumpEvent
            newBolusEntry.amount = amount as NSDecimalNumber
            newBolusEntry.isExternal = true // we are creating an external dose
            newBolusEntry.isSMB = false // the dose is manually administered

            do {
                guard self.context.hasChanges else { return }
                try self.context.save()
                debug(.coreData, "External insulin saved")
                self.updateSubject.send(())
            } catch {
                debug(.coreData, "Failed to store external insulin in context: \(error)")
            }
        }
    }

    func getPumpHistory() async throws -> [PumpHistoryEvent] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: false
        )

        return await context.perform {
            guard let fetchedPumpEvents = results as? [PumpEventStored] else { return [] }

            return fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEventStored.EventType.bolus.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .bolus,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.bolus?.amount as Decimal?
                    )
                case PumpEventStored.EventType.tempBasal.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .tempBasal,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.tempBasal?.rate as Decimal?,
                        duration: Int(event.tempBasal?.duration ?? 0),
                        isScheduledBasal: event.tempBasal?.isScheduledBasal ?? false
                    )
                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }

    func determineBolusEventType(for event: PumpEventStored) -> PumpEventStored.EventType {
        guard let bolus = event.bolus else {
            return event.type.flatMap({ PumpEventStored.EventType(rawValue: $0) }) ?? .bolus
        }
        if bolus.isSMB {
            return .smb
        }
        if bolus.isExternal {
            return .isExternal
        }
        return event.type.flatMap({ PumpEventStored.EventType(rawValue: $0) }) ?? .bolus
    }

    func getPumpHistoryNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpEventsNotYetUploadedToNightscout,
            key: "timestamp",
            ascending: false
        )

        return try await context.perform { [self] in
            guard let fetchedPumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEvent.bolus.rawValue:
                    // eventType determines whether bolus is external, smb or manual (=administered via app by user)
                    let eventType = determineBolusEventType(for: event)
                    return NightscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: eventType,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: event.bolus?.amount as Decimal?,
                        notes: nil,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil,
                        id: event.id
                    )
                case PumpEvent.tempBasal.rawValue:
                    return NightscoutTreatment(
                        duration: Int(event.tempBasal?.duration ?? 0),
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: event.tempBasal?.rate as Decimal?,
                        rate: event.tempBasal?.rate as Decimal?,
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
                        targetBottom: nil,
                        id: event.id
                    )
                case PumpEvent.pumpSuspend.rawValue:
                    return NightscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsNote,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: nil,
                        notes: PumpEvent.pumpSuspend.rawValue,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil
                    )
                case PumpEvent.pumpResume.rawValue:
                    return NightscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsNote,
                        createdAt: event.timestamp,
                        enteredBy: NightscoutTreatment.local,
                        bolus: nil,
                        insulin: nil,
                        notes: PumpEvent.pumpResume.rawValue,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil
                    )
                case PumpEvent.rewind.rawValue:
                    return NightscoutTreatment(
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
                case PumpEvent.siteChange.rawValue:
                    return NightscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsSiteChange,
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
                case PumpEvent.pumpAlarm.rawValue:
                    return NightscoutTreatment(
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
                        notes: "Alarm \(String(describing: event.note)) \(PumpEvent.pumpAlarm.rawValue)",
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil
                    )

                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }

    func getPumpHistoryNotYetUploadedToHealth() async throws -> [PumpHistoryEvent] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpEventsNotYetUploadedToHealth,
            key: "timestamp",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedPumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEvent.bolus.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .bolus,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.bolus?.amount as Decimal?
                    )
                case PumpEvent.tempBasal.rawValue:
                    if let id = event.id, let timestamp = event.timestamp, let tempBasal = event.tempBasal,
                       let tempBasalRate = tempBasal.rate
                    {
                        return PumpHistoryEvent(
                            id: id,
                            type: .tempBasal,
                            timestamp: timestamp,
                            amount: tempBasalRate as Decimal,
                            duration: Int(tempBasal.duration)
                        )
                    } else {
                        return nil
                    }
                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }

    func getPumpHistoryNotYetUploadedToTidepool() async throws -> [PumpHistoryEvent] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpEventsNotYetUploadedToTidepool,
            key: "timestamp",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedPumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEvent.bolus.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .bolus,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.bolus?.amount as Decimal?,
                        isSMB: event.bolus?.isSMB ?? true,
                        isExternal: event.bolus?.isExternal ?? false
                    )
                case PumpEvent.tempBasal.rawValue:
                    if let id = event.id, let timestamp = event.timestamp, let tempBasal = event.tempBasal,
                       let tempBasalRate = tempBasal.rate
                    {
                        return PumpHistoryEvent(
                            id: id,
                            type: .tempBasal,
                            timestamp: timestamp,
                            amount: tempBasalRate as Decimal,
                            duration: Int(tempBasal.duration)
                        )
                    } else {
                        return nil
                    }

                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }
}

extension BasePumpHistoryStorage {
    /// Fallback upsert key for events without a dose identifier.
    struct TimestampAndType: Hashable {
        let timestamp: Date
        let type: String
    }
}

extension PumpEventType {
    /// Scheduled-basal reports become TBR rows tagged `isScheduledBasal`.
    var storedEventType: PumpEventStored.EventType? {
        switch self {
        case .alarm: return .pumpAlarm
        case .alarmClear: return nil
        case .basal: return .tempBasal
        case .bolus: return .bolus
        case .prime: return .prime
        case .resume: return .pumpResume
        case .rewind: return .rewind
        case .suspend: return .pumpSuspend
        case .tempBasal: return .tempBasal
        case .replaceComponent(componentType: .infusionSet),
             .replaceComponent(componentType: .pump): return .siteChange
        case .replaceComponent: return nil
        @unknown default: return nil
        }
    }
}
