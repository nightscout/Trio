import Foundation
@testable import Trio

/// Deterministic input builders for the parity golden scenarios.
enum ParityInputs {
    // MARK: - Profile inputs

    static func pumpSettings() -> PumpSettings {
        PumpSettings(insulinActionCurve: 9, maxBolus: 10, maxBasal: 4)
    }

    static func bgTargets() -> BGTargets {
        BGTargets(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            targets: [
                BGTargetEntry(low: 100, high: 100, start: "00:00:00", offset: 0),
                BGTargetEntry(low: 95, high: 95, start: "06:00:00", offset: 360),
                BGTargetEntry(low: 105, high: 105, start: "21:00:00", offset: 1260)
            ]
        )
    }

    static func basalProfile() -> [BasalProfileEntry] {
        [
            BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.8),
            BasalProfileEntry(start: "06:00:00", minutes: 360, rate: 1.2),
            BasalProfileEntry(start: "12:00:00", minutes: 720, rate: 0.9),
            BasalProfileEntry(start: "22:00:00", minutes: 1320, rate: 0.7)
        ]
    }

    static func isf() -> InsulinSensitivities {
        InsulinSensitivities(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            sensitivities: [
                InsulinSensitivityEntry(sensitivity: 50, offset: 0, start: "00:00:00"),
                InsulinSensitivityEntry(sensitivity: 45, offset: 360, start: "06:00:00"),
                InsulinSensitivityEntry(sensitivity: 55, offset: 720, start: "12:00:00")
            ]
        )
    }

    static func carbRatios() -> CarbRatios {
        CarbRatios(
            units: .grams,
            schedule: [
                CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 10),
                CarbRatioEntry(start: "12:00:00", offset: 720, ratio: 12)
            ]
        )
    }

    static func orefVariables(clock: Date) -> TrioCustomOrefVariables {
        TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: clock,
            overridePercentage: 100,
            useOverride: false,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )
    }

    // MARK: - Glucose traces (newest-first, 5-min cadence, ending at clock)

    static func trace(endingAt clock: Date, values: [Int]) -> [BloodGlucose] {
        let start = clock.addingTimeInterval(TimeInterval(-(values.count - 1) * 300))
        return values.enumerated().map { index, sgv in
            let timestamp = start.addingTimeInterval(TimeInterval(index * 300))
            return BloodGlucose(
                id: "bg-\(index)",
                sgv: sgv,
                date: Decimal(timestamp.timeIntervalSince1970 * 1000),
                dateString: timestamp,
                glucose: sgv
            )
        }.reversed()
    }

    /// 24h (288 values, oldest first) around `base` with a deterministic wobble,
    /// ending in `tail` (which replaces the last tail.count values).
    static func values24h(base: Int, tail: [Int] = []) -> [Int] {
        var values = (0 ..< 288).map { base + ($0 * 7 % 5) - 2 }
        if !tail.isEmpty {
            values.replaceSubrange((values.count - tail.count) ..< values.count, with: tail)
        }
        return values
    }

    /// 24h drift from `from` to `to` with wobble — sustained deviations for autosens.
    static func drift24h(from: Int, to: Int) -> [Int] {
        (0 ..< 288).map { index in
            from + (to - from) * index / 287 + (index * 7 % 5) - 2
        }
    }

    // MARK: - Pump history (newest-first not required; generators sort internally)

    static func tempBasalPair(id: Int, at timestamp: Date, rate: Decimal, duration: Int) -> [PumpHistoryEvent] {
        [
            PumpHistoryEvent(id: "tb-\(id)", type: .tempBasal, timestamp: timestamp, rate: rate, temp: .absolute),
            PumpHistoryEvent(id: "tbd-\(id)", type: .tempBasalDuration, timestamp: timestamp, durationMin: duration)
        ]
    }

    static func bolus(id: Int, at timestamp: Date, amount: Decimal, isSMB: Bool = false) -> PumpHistoryEvent {
        PumpHistoryEvent(id: "bolus-\(id)", type: isSMB ? .smb : .bolus, timestamp: timestamp, amount: amount, isSMB: isSMB)
    }

    /// 24h of realistic history: 48 temp basals (30-min cadence), 12 boluses,
    /// 8 SMBs, one suspend/resume window and a site change.
    static func densePumpHistory(clock: Date) -> [PumpHistoryEvent] {
        var events: [PumpHistoryEvent] = []
        let rates: [Decimal] = [0, 0.5, 1.5, 2.25, 1.0, 0.25, 1.75, 0.75]
        for index in 0 ..< 48 {
            let timestamp = clock.addingTimeInterval(TimeInterval(-(index * 30 + 5) * 60))
            events += tempBasalPair(id: index, at: timestamp, rate: rates[index % rates.count], duration: 30)
        }
        for index in 0 ..< 12 {
            let timestamp = clock.addingTimeInterval(TimeInterval(-(index * 120 + 17) * 60))
            events.append(bolus(id: index, at: timestamp, amount: 1 + Decimal(index % 4) * 0.55))
        }
        for index in 0 ..< 8 {
            let timestamp = clock.addingTimeInterval(TimeInterval(-(index * 180 + 47) * 60))
            events.append(bolus(id: 100 + index, at: timestamp, amount: 0.4, isSMB: true))
        }
        events.append(PumpHistoryEvent(id: "suspend-1", type: .pumpSuspend, timestamp: clock.addingTimeInterval(-16.5 * 3600)))
        events.append(PumpHistoryEvent(id: "resume-1", type: .pumpResume, timestamp: clock.addingTimeInterval(-16 * 3600)))
        events.append(PumpHistoryEvent(id: "rewind-1", type: .rewind, timestamp: clock.addingTimeInterval(-20 * 3600)))
        events.append(PumpHistoryEvent(id: "prime-1", type: .prime, timestamp: clock.addingTimeInterval(-19.9 * 3600)))
        return events
    }

    /// Sparse history: a few temp basals and one bolus.
    static func lightPumpHistory(clock: Date) -> [PumpHistoryEvent] {
        var events: [PumpHistoryEvent] = []
        for index in 0 ..< 6 {
            let timestamp = clock.addingTimeInterval(TimeInterval(-(index * 60 + 10) * 60))
            events += tempBasalPair(id: index, at: timestamp, rate: Decimal(index % 3), duration: 30)
        }
        events.append(bolus(id: 0, at: clock.addingTimeInterval(-2.5 * 3600), amount: 2.0))
        return events
    }
}
