import Foundation
import LoopKit
import SwiftDate
import Swinject

protocol PumpHistoryObserver {
    func pumpHistoryDidUpdate(_ events: [PumpHistoryEvent])
}

protocol PumpHistoryStorage {
    func storePumpEvents(_ events: [NewPumpEvent])
    func storeEvents(_ events: [PumpHistoryEvent])
    func storeJournalCarbs(_ carbs: Int)
    func recent() -> [PumpHistoryEvent]
    func nightscoutTreatmentsNotUploaded() -> [NightscoutTreatment]
    func saveCancelTempEvents()
    func deleteInsulin(at date: Date)
}

final class BasePumpHistoryStorage: PumpHistoryStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BasePumpHistoryStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storePumpEvents(_ events: [NewPumpEvent]) {
        processQueue.async {
            let eventsToStore = events.flatMap { event -> [PumpHistoryEvent] in
                let id = event.raw.md5String
                switch event.type {
                case .bolus:
                    guard let dose = event.dose else { return [] }
                    let amount = Decimal(string: dose.unitsInDeliverableIncrements.description)
                    let minutes = Int((dose.endDate - dose.startDate).timeInterval / 60)
                    return [PumpHistoryEvent(
                        id: id,
                        type: .bolus,
                        timestamp: event.date,
                        amount: amount,
                        duration: minutes,
                        durationMin: nil,
                        rate: nil,
                        temp: nil,
                        carbInput: nil,
                        isSMB: dose.automatic,
                        isExternalInsulin: dose.manuallyEntered
                    )]
                case .tempBasal:
                    guard let dose = event.dose else { return [] }

                    let rate = Decimal(dose.unitsPerHour)
                    let minutes = (dose.endDate - dose.startDate).timeInterval / 60
                    let delivered = dose.deliveredUnits
                    let date = event.date

                    let isCancel = delivered != nil //! event.isMutable && delivered != nil
                    guard !isCancel else { return [] }

                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .tempBasalDuration,
                            timestamp: date,
                            amount: nil,
                            duration: nil,
                            durationMin: Int(round(minutes)),
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        ),
                        PumpHistoryEvent(
                            id: "_" + id,
                            type: .tempBasal,
                            timestamp: date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: rate,
                            temp: .absolute,
                            carbInput: nil
                        )
                    ]
                case .suspend:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpSuspend,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .resume:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpResume,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .rewind:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .rewind,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .prime:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .prime,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .alarm:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpAlarm,
                            timestamp: event.date,
                            note: event.title
                        )
                    ]
                default:
                    return []
                }
            }

            self.storeEvents(eventsToStore)
        }
    }

    func storeJournalCarbs(_ carbs: Int) {
        processQueue.async {
            let eventsToStore = [
                PumpHistoryEvent(
                    id: UUID().uuidString,
                    type: .journalCarbs,
                    timestamp: Date(),
                    amount: nil,
                    duration: nil,
                    durationMin: nil,
                    rate: nil,
                    temp: nil,
                    carbInput: carbs
                )
            ]
            self.storeEvents(eventsToStore)
        }
    }

    func storeEvents(_ events: [PumpHistoryEvent]) {
        processQueue.async {
            let file = OpenAPS.Monitor.pumpHistory
            var uniqEvents: [PumpHistoryEvent] = []
            self.storage.transaction { storage in
                storage.append(events, to: file, uniqBy: \.id)
                uniqEvents = storage.retrieve(file, as: [PumpHistoryEvent].self)?
                    .filter { $0.timestamp.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.timestamp > $1.timestamp } ?? []
                storage.save(Array(uniqEvents), as: file)
            }
            self.broadcaster.notify(PumpHistoryObserver.self, on: self.processQueue) {
                $0.pumpHistoryDidUpdate(uniqEvents)
            }
        }
    }

    func recent() -> [PumpHistoryEvent] {
        storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self)?.reversed() ?? []
    }

    func deleteInsulin(at date: Date) {
        processQueue.sync {
            var allValues = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) ?? []
            guard let entryIndex = allValues.firstIndex(where: { $0.timestamp == date }) else {
                return
            }
            allValues.remove(at: entryIndex)
            storage.save(allValues, as: OpenAPS.Monitor.pumpHistory)
            broadcaster.notify(PumpHistoryObserver.self, on: processQueue) {
                $0.pumpHistoryDidUpdate(allValues)
            }
        }
    }

    func nightscoutTreatmentsNotUploaded() -> [NightscoutTreatment] {
        let events = recent()
        guard !events.isEmpty else { return [] }

        var treatments: [NightscoutTreatment?] = []

        for i in 0 ..< events.count {
            let event = events[i]
            var nextEvent: PumpHistoryEvent?
            if i + 1 < events.count {
                nextEvent = events[i + 1]
            }
            if event.type == .tempBasal, nextEvent?.type == .tempBasalDuration {
                treatments.append(NightscoutTreatment(event: event, tempBasalDuration: nextEvent))
            } else {
                treatments.append(NightscoutTreatment(event: event))
            }
        }

        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedPumphistory, as: [NightscoutTreatment].self) ?? []

        let treatmentsToUpload = Set(treatments.compactMap { $0 }).subtracting(Set(uploaded))

        return treatmentsToUpload.sorted { $0.createdAt! > $1.createdAt! }
    }

    func saveCancelTempEvents() {
        let basalID = UUID().uuidString
        let date = Date()

        let events = [
            PumpHistoryEvent(
                id: basalID,
                type: .tempBasalDuration,
                timestamp: date,
                amount: nil,
                duration: nil,
                durationMin: 0,
                rate: nil,
                temp: nil,
                carbInput: nil
            ),
            PumpHistoryEvent(
                id: "_" + basalID,
                type: .tempBasal,
                timestamp: date,
                amount: nil,
                duration: nil,
                durationMin: nil,
                rate: 0,
                temp: .absolute,
                carbInput: nil
            )
        ]

        storeEvents(events)
    }
}

extension NightscoutTreatment {
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
