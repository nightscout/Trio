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
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    private let updateSubject = PassthroughSubject<Void, Never>()

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    private let context: NSManagedObjectContext

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
            for event in events {
                let existingEvents: [PumpEventStored] = try CoreDataStack.shared.fetchEntities(
                    ofType: PumpEventStored.self,
                    onContext: self.context,
                    predicate: NSPredicate.duplicates(event.date),
                    key: "timestamp",
                    ascending: false,
                    batchSize: 50
                ) as? [PumpEventStored] ?? []

                switch event.type {
                case .bolus:

                    guard let dose = event.dose else { continue }
                    let amount = self.roundDose(
                        dose.unitsInDeliverableIncrements,
                        toIncrement: Double(self.settings.preferences.bolusIncrement)
                    )

                    guard existingEvents.isEmpty else {
                        // Duplicate found, do not store the event
                        debug(.coreData, "Duplicate event found with timestamp: \(event.date)")

                        if let existingEvent = existingEvents.first(where: { $0.type == EventType.bolus.rawValue }) {
                            if existingEvent.timestamp == event.date {
                                if let existingAmount = existingEvent.bolus?.amount, amount < existingAmount as Decimal {
                                    // Update existing event with new smaller value
                                    existingEvent.bolus?.amount = amount as NSDecimalNumber
                                    existingEvent.bolus?.isSMB = dose.automatic ?? true
                                    existingEvent.isUploadedToNS = false
                                    existingEvent.isUploadedToHealth = false
                                    existingEvent.isUploadedToTidepool = false

                                    debug(.coreData, "Updated existing event with smaller value: \(amount)")
                                }
                            }
                        }
                        continue
                    }

                    let newPumpEvent = PumpEventStored(context: self.context)
                    newPumpEvent.id = UUID().uuidString
                    // restrict entry to now or past
                    newPumpEvent.timestamp = event.date > Date() ? Date() : event.date
                    newPumpEvent.type = PumpEvent.bolus.rawValue
                    newPumpEvent.isUploadedToNS = false
                    newPumpEvent.isUploadedToHealth = false
                    newPumpEvent.isUploadedToTidepool = false

                    let newBolusEntry = BolusStored(context: self.context)
                    newBolusEntry.pumpEvent = newPumpEvent
                    newBolusEntry.amount = NSDecimalNumber(decimal: amount)
                    newBolusEntry.isExternal = dose.manuallyEntered
                    newBolusEntry.isSMB = dose.automatic ?? true

                case .tempBasal:
                    guard let dose = event.dose else { continue }

                    guard existingEvents.isEmpty else {
                        // Duplicate found, do not store the event
                        debug(.coreData, "Duplicate event found with timestamp: \(event.date)")
                        continue
                    }

                    let rate = Decimal(dose.unitsPerHour)
                    let minutes = (dose.endDate - dose.startDate).timeInterval / 60
                    let delivered = dose.deliveredUnits
                    let date = event.date

                    let isCancel = delivered != nil
                    guard !isCancel else { continue }

                    let newPumpEvent = PumpEventStored(context: self.context)
                    newPumpEvent.id = UUID().uuidString
                    newPumpEvent.timestamp = date
                    newPumpEvent.type = PumpEvent.tempBasal.rawValue
                    newPumpEvent.isUploadedToNS = false
                    newPumpEvent.isUploadedToHealth = false
                    newPumpEvent.isUploadedToTidepool = false

                    let newTempBasal = TempBasalStored(context: self.context)
                    newTempBasal.pumpEvent = newPumpEvent
                    newTempBasal.duration = Int16(round(minutes))
                    newTempBasal.rate = rate as NSDecimalNumber
                    newTempBasal.tempType = TempType.absolute.rawValue

                case .suspend:
                    guard existingEvents.isEmpty else {
                        // Duplicate found, do not store the event
                        debug(.coreData, "Duplicate event found with timestamp: \(event.date)")
                        continue
                    }
                    let newPumpEvent = PumpEventStored(context: self.context)
                    newPumpEvent.id = UUID().uuidString
                    newPumpEvent.timestamp = event.date
                    newPumpEvent.type = PumpEvent.pumpSuspend.rawValue
                    newPumpEvent.isUploadedToNS = false
                    newPumpEvent.isUploadedToHealth = false
                    newPumpEvent.isUploadedToTidepool = false

                case .resume:
                    guard existingEvents.isEmpty else {
                        // Duplicate found, do not store the event
                        debug(.coreData, "Duplicate event found with timestamp: \(event.date)")
                        continue
                    }
                    let newPumpEvent = PumpEventStored(context: self.context)
                    newPumpEvent.id = UUID().uuidString
                    newPumpEvent.timestamp = event.date
                    newPumpEvent.type = PumpEvent.pumpResume.rawValue
                    newPumpEvent.isUploadedToNS = false
                    newPumpEvent.isUploadedToHealth = false
                    newPumpEvent.isUploadedToTidepool = false

                case .rewind:
                    guard existingEvents.isEmpty else {
                        // Duplicate found, do not store the event
                        debug(.coreData, "Duplicate event found with timestamp: \(event.date)")
                        continue
                    }
                    let newPumpEvent = PumpEventStored(context: self.context)
                    newPumpEvent.id = UUID().uuidString
                    newPumpEvent.timestamp = event.date
                    newPumpEvent.type = PumpEvent.rewind.rawValue
                    newPumpEvent.isUploadedToNS = false
                    newPumpEvent.isUploadedToHealth = false
                    newPumpEvent.isUploadedToTidepool = false

                case .prime:
                    guard existingEvents.isEmpty else {
                        // Duplicate found, do not store the event
                        debug(.coreData, "Duplicate event found with timestamp: \(event.date)")
                        continue
                    }
                    let newPumpEvent = PumpEventStored(context: self.context)
                    newPumpEvent.id = UUID().uuidString
                    newPumpEvent.timestamp = event.date
                    newPumpEvent.type = PumpEvent.prime.rawValue
                    newPumpEvent.isUploadedToNS = false
                    newPumpEvent.isUploadedToHealth = false
                    newPumpEvent.isUploadedToTidepool = false

                case .alarm:
                    guard existingEvents.isEmpty else {
                        // Duplicate found, do not store the event
                        debug(.coreData, "Duplicate event found with timestamp: \(event.date)")
                        continue
                    }
                    let newPumpEvent = PumpEventStored(context: self.context)
                    newPumpEvent.id = UUID().uuidString
                    newPumpEvent.timestamp = event.date
                    newPumpEvent.type = PumpEvent.pumpAlarm.rawValue
                    newPumpEvent.isUploadedToNS = false
                    newPumpEvent.isUploadedToHealth = false
                    newPumpEvent.isUploadedToTidepool = false
                    newPumpEvent.note = event.title

                default:
                    continue
                }
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

    func storeExternalInsulinEvent(amount: Decimal, timestamp: Date) async {
        await context.perform {
            // create pump event
            let newPumpEvent = PumpEventStored(context: self.context)
            newPumpEvent.id = UUID().uuidString
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
            ascending: false,
            fetchLimit: 288
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
                        duration: Int(event.tempBasal?.duration ?? 0)
                    )
                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }

    func determineBolusEventType(for event: PumpEventStored) -> PumpEventStored.EventType {
        if event.bolus!.isSMB {
            return .smb
        }
        if event.bolus!.isExternal {
            return .isExternal
        }
        return PumpEventStored.EventType(rawValue: event.type!) ?? PumpEventStored.EventType.bolus
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
                case PumpEvent.prime.rawValue:
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
