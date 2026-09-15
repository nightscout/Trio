import Foundation

extension PumpHistoryEvent {
    /// Helper function that we use when filtering pump history events
    func isSuspendOrResume() -> Bool {
        type == .pumpSuspend || type == .pumpResume
    }

    func computedEvent() -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration.map { Decimal($0) },
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: nil
        )
    }
}

extension ComputedPumpHistoryEvent {
    func copyWith(duration: Decimal?) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    func copyWith(duration: Decimal, timestamp: Date) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    func copyWith(duration: Decimal, timestamp: Date, omitFromTempHistory: Bool) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    func copyWith(insulin: Decimal?) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    func copyWith(rate: Decimal?) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: id,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    // Warning: we're using .tempBasal here since there isn't a 'SuspendBasal' case
    // but the JS code says it's just for debugging
    static func suspendBasal(timestamp: Date, duration: Decimal?) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: UUID().uuidString,
            type: .tempBasal,
            timestamp: timestamp,
            amount: nil,
            duration: duration,
            durationMin: nil,
            rate: 0,
            temp: .absolute,
            carbInput: nil,
            fatInput: nil,
            proteinInput: nil,
            note: nil,
            isSMB: nil,
            isExternal: nil,
            insulin: nil
        )
    }

    static func zeroTempBasal(timestamp: Date, duration: Decimal, omitFromTempHistory: Bool) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: UUID().uuidString,
            type: .tempBasal,
            timestamp: timestamp,
            amount: nil,
            duration: duration,
            durationMin: nil,
            rate: 0,
            temp: nil,
            carbInput: nil,
            fatInput: nil,
            proteinInput: nil,
            note: nil,
            isSMB: nil,
            isExternal: nil,
            insulin: nil,
            omitFromTempHistory: omitFromTempHistory
        )
    }

    static func tempBolus(timestamp: Date, insulin: Decimal) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: UUID().uuidString,
            type: .bolus,
            timestamp: timestamp,
            amount: nil,
            duration: nil,
            durationMin: nil,
            rate: nil,
            temp: nil,
            carbInput: nil,
            fatInput: nil,
            proteinInput: nil,
            note: nil,
            isSMB: nil,
            isExternal: nil,
            insulin: insulin,
            isTempBolus: true
        )
    }

    static func forTest(
        type: EventType,
        timestamp: Date,
        amount: Decimal? = nil,
        duration: Decimal? = nil,
        durationMin: Int? = nil,
        rate: Decimal? = nil,
        temp: TempType? = nil,
        carbInput: Int? = nil,
        fatInput: Int? = nil,
        proteinInput: Int? = nil,
        note: String? = nil,
        isSMB: Bool? = nil,
        isExternal: Bool? = nil,
        insulin: Decimal? = nil
    ) -> ComputedPumpHistoryEvent {
        ComputedPumpHistoryEvent(
            id: UUID().uuidString,
            type: type,
            timestamp: timestamp,
            amount: amount,
            duration: duration,
            durationMin: durationMin,
            rate: rate,
            temp: temp,
            carbInput: carbInput,
            fatInput: fatInput,
            proteinInput: proteinInput,
            note: note,
            isSMB: isSMB,
            isExternal: isExternal,
            insulin: insulin
        )
    }
}
