//
//  DoseStore.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/31/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKit


// Bridges support for MinimedKit data types
extension Collection where Element == TimestampedHistoryEvent {
    
    func pumpEvents(from model: PumpModel) -> [NewPumpEvent] {
        var events: [NewPumpEvent] = []
        var lastTempBasal: DoseEntry?
        var lastSuspend: DoseEntry?
        // Always assume the sequence may have started rewound. LoopKit will ignore unmatched resume events.
        var isRewound = true
        var title: String
        let now = Date()

        for event in self {
            var dose: DoseEntry?
            var eventType: LoopKit.PumpEventType?

            title = String(describing: type(of: event.pumpEvent))

            switch event.pumpEvent {
            case let bolus as BolusNormalPumpEvent:
                title = LocalizedString("Bolus", comment: "Event title for bolus")
                let bolusEndDate: Date
                if let lastSuspend = lastSuspend, bolus.programmed != bolus.amount, lastSuspend.startDate > event.date {
                    bolusEndDate = lastSuspend.startDate
                } else if bolus.duration > 0 {
                    bolusEndDate = event.date.addingTimeInterval(bolus.duration)
                } else {
                    bolusEndDate = event.date.addingTimeInterval(model.bolusDeliveryTime(units: bolus.amount))
                }
                var automatic: Bool?
                if !bolus.wasRemotelyTriggered {
                    automatic = false
                }
                dose = DoseEntry(type: .bolus, startDate: event.date, endDate: bolusEndDate, value: bolus.programmed, unit: .units, deliveredUnits: bolus.amount, automatic: automatic, isMutable: bolus.isMutable(atDate: now, forPump: model), wasProgrammedByPumpUI: !bolus.wasRemotelyTriggered)
            case let suspendEvent as SuspendPumpEvent:
                title = LocalizedString("Suspend", comment: "Event title for suspend")
                dose = DoseEntry(suspendDate: event.date, wasProgrammedByPumpUI: !suspendEvent.wasRemotelyTriggered)
                lastSuspend = dose
            case let resumeEvent as ResumePumpEvent:
                title = LocalizedString("Resume", comment: "Event title for resume")
                dose = DoseEntry(resumeDate: event.date, wasProgrammedByPumpUI: !resumeEvent.wasRemotelyTriggered)
            case let temp as TempBasalPumpEvent:
                if case .Absolute = temp.rateType {
                    lastTempBasal = DoseEntry(type: .tempBasal, startDate: event.date, value: temp.rate, unit: .unitsPerHour, isMutable: false, wasProgrammedByPumpUI: !temp.wasRemotelyTriggered)
                    continue
                } else {
                    title = LocalizedString("Percent Temp Basal", comment: "Event title for percent based temp basal")
                }
            case let tempDuration as TempBasalDurationPumpEvent:
                if let lastTemp = lastTempBasal, lastTemp.startDate == event.date {
                    if tempDuration.duration == 0 {
                        title = LocalizedString("Cancel Temp Basal", comment: "Event title for temp basal cancel")
                    } else {
                        title = LocalizedString("Temp Basal", comment: "Event title for temporary basal rate start")
                    }

                    // Temp basal events in mdt pump history are not mutable, but we report mutability to Loop as
                    // indicating whether we will be mutating this DoseEntry in the future, and until this TempBasal
                    // Is finished or canceled it is still mutable.

                    let endDate = event.date.addingTimeInterval(TimeInterval(minutes: Double(tempDuration.duration)))
                    let isMutable = endDate < now

                    dose = DoseEntry(
                        type: .tempBasal,
                        startDate: event.date,
                        endDate: endDate,
                        value: lastTemp.unitsPerHour,
                        unit: .unitsPerHour,
                        automatic: false, // If this was automatic dose, it should be set as such during reconciliation
                        isMutable: isMutable,
                        wasProgrammedByPumpUI: lastTemp.wasProgrammedByPumpUI
                    )
                }
            case let basal as BasalProfileStartPumpEvent:
                title = LocalizedString("Scheduled Basal", comment: "Event title for starting scheduled basal")
                dose = DoseEntry(
                    type: .basal,
                    startDate: event.date,
                    // Use the maximum-possible duration for a basal entry; its true duration will be reconciled against other entries.
                    endDate: event.date.addingTimeInterval(.hours(24)),
                    value: basal.scheduleEntry.rate,
                    unit: .unitsPerHour,
                    isMutable: false
                )
            case is RewindPumpEvent:
                title = LocalizedString("Rewind", comment: "Event title for rewind")
                eventType = .rewind

                /* 
                 No insulin is delivered between the beginning of a rewind until the suggested fixed prime is delivered or cancelled.
 
                 If the fixed prime is cancelled, it is never recorded in history. It is possible to cancel a fixed prime and perform one manually some time later, but basal delivery will have resumed during that period.
                 
                 We take the conservative approach and assume delivery is paused only between the Rewind and the first Prime event.
                 */
                dose = DoseEntry(suspendDate: event.date)
                isRewound = true
            case let prime as PrimePumpEvent:
                title = LocalizedString("Prime", comment: "Event title for prime pump event")
                eventType = .prime

                if prime.primeType == .fixed {
                    let setChangeRaw = "SetChange\(event.date)".data(using: .utf8)!
                    events.append(NewPumpEvent(date: event.date, dose: nil, raw: setChangeRaw, title: "Set Change (fixed prime)", type: .replaceComponent(componentType:
                            .infusionSet)))
                }

                if isRewound {
                    isRewound = false
                    dose = DoseEntry(resumeDate: event.date)
                }
            case let alarm as PumpAlarmPumpEvent:
                title = alarm.alarmType.localizedString
                eventType = .alarm

                if case .noDelivery = alarm.alarmType {
                    dose = DoseEntry(suspendDate: event.date)
                }
                break
            case let alarm as ClearAlarmPumpEvent:
                title = LocalizedString("Clear Alarm", comment: "Event title for clear alarm pump event")
                eventType = .alarmClear

                if case .noDelivery = alarm.alarmType {
                    dose = DoseEntry(resumeDate: event.date)
                }
                break
            case is JournalEntryMealMarkerPumpEvent:
                title = LocalizedString("Meal", comment: "Event title for JournalEntryMealMarkerPumpEvent")
                break
            case is JournalEntryPumpLowBatteryPumpEvent:
                title = LocalizedString("Low Battery", comment: "Event title for JournalEntryPumpLowBatteryPumpEvent")
                break
            case is JournalEntryPumpLowReservoirPumpEvent:
                title = LocalizedString("Low Reservoir", comment: "Event title for JournalEntryPumpLowReservoirPumpEvent")
                break
            case is ChangeBasalProfilePumpEvent:
                title = LocalizedString("Change Basal Schedule", comment: "Event title for ChangeBasalProfilePumpEvent")
                break
            case is ChangeBasalProfilePatternPumpEvent:
                title = LocalizedString("Change Basal Profile Schedule", comment: "Event title for ChangeBasalProfilePatternPumpEvent")
                break
            case is SelectBasalProfilePumpEvent:
                title = LocalizedString("Select Profile", comment: "Event title for SelectBasalProfilePumpEvent")
                break
            case is ChangeTimePumpEvent:
                title = LocalizedString("Change Time", comment: "Event title for ChangeTimePumpEvent")
                break
            case is NewTimePumpEvent:
                title = LocalizedString("New Time", comment: "Event title for NewTimePumpEvent")
                break
            default:
                break
            }

            events.append(NewPumpEvent(date: event.date, dose: dose, raw: event.pumpEvent.rawData, title: title, type: eventType))
        }

        return events
    }
}
