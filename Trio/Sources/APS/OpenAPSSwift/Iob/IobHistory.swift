import Foundation

/// The Javascript implementation was too complex to port directly, so this is a clean implementation
/// of the original logic. There are a few differences:
///  - We are more strict in error checking
///  - We ignore event types that Trio won't send us
///  - We exclude some redundant events (shouldn't impact the IoB calculation)
///
///  There is one area where we changed the implementation that could impact IoB calculations
///  - We don't split temp basals that cross suspends -- after a suspend resumes we assume that
///     it goes back to the profile basal rate
///
///  From looking at the implementat, the `suspendZerosIob` should just be on by default to
///  handle pump suspensions correctly
///
///  The current Javascript implementation is an approximation of IoB, but we have an issue
///  open to update to more accurate pump events: https://github.com/nightscout/Trio-dev/issues/325
///  And to fix the suspend logic: https://github.com/nightscout/Trio-dev/issues/357
///
///  Also, the current Javascript implementation implements the approximate algorithm incorrectly in
///  a few corner cases:
///  - If a tempBasal is longer than 30 minutes and has a profile basal rate change in the middle, it will
///   miss this split resulting in incorrect insulin calculations.
///  - When splitting events, it uses minutes instead of seconds or milliseconds to calculate durations,
///   which can lead to incorrect durations.
///
/// These seem like small issues, and they are, but I have seen both in my data over a few days of running.

struct IobHistory {
    /// Used for calculating the beginning of a 0 temp when the pump history begins suspended
    static let MAX_PUMP_HISTORY_HOURS: Double = 36

    struct PumpSuspended {
        let timestamp: Date
        let durationInMinutes: Decimal

        // these two properties are used to mark the first resume
        // and last suspend if the pump is suspended when the history
        // begins or currently suspended respectively
        let isSuspendedPrior: Bool
        let isCurrentlySuspended: Bool

        init(timestamp: Date, durationInMinutes: Decimal, isSuspendedPrior: Bool = false, isCurrentlySuspended: Bool = false) {
            self.timestamp = timestamp
            self.durationInMinutes = durationInMinutes
            self.isSuspendedPrior = isSuspendedPrior
            self.isCurrentlySuspended = isCurrentlySuspended
        }

        var end: Date {
            timestamp + durationInMinutes.minutesToSeconds
        }

        func doesOverlap(with event: ComputedPumpHistoryEvent) -> Bool {
            guard let eventDuration = event.duration else {
                return event.timestamp >= timestamp && event.timestamp < end
            }
            let eventEnd = event.timestamp + eventDuration.minutesToSeconds

            return event.timestamp < end && timestamp < eventEnd
        }
    }

    /// Processes and extract temp basals from a pumpHistory.
    ///
    /// The core algorithm here is to combine `TempBasal` and `TempBasalDuration`
    /// events into a single TempBasal event with a duration. It also adds a zeroTempBasal at the end
    /// and makes sure that none of the temp basals overlap.
    private static func getTempBasals(
        pumpHistory: [ComputedPumpHistoryEvent],
        clock: Date,
        zeroTempDuration: Decimal?
    ) throws -> [ComputedPumpHistoryEvent] {
        let tempBasals = pumpHistory.filter { $0.type == .tempBasal }
        let durations = pumpHistory.filter { $0.type == .tempBasalDuration }

        guard tempBasals.count == durations.count else {
            throw IobError.tempBasalDurationMismatch
        }

        // this stops the most recent temp basal, the 1m comes from Javascript
        let zeroTempBasal = ComputedPumpHistoryEvent.zeroTempBasal(
            timestamp: clock + 1.minutesToSeconds,
            duration: zeroTempDuration ?? 0,
            omitFromTempHistory: false
        )

        // match temp basal entries to their duration entry
        let unifiedTempBasals = try zip(tempBasals, durations).map { tempBasal, duration in
            guard tempBasal.timestamp == duration.timestamp else {
                throw IobError.tempBasalDurationMismatch
            }

            guard let duration = duration.durationMin else {
                throw IobError.tempBasalDurationMissingDuration(timestamp: duration.timestamp)
            }

            return tempBasal.copyWith(duration: Decimal(duration))
        } + [zeroTempBasal]

        // if any of our temp basals overlap, truncate
        let alignedTempBasals = zip(unifiedTempBasals, unifiedTempBasals.dropFirst()).map { curr, next in

            let currEnd = curr.timestamp + (curr.duration?.minutesToSeconds ?? 0)
            if currEnd > next.timestamp {
                let newDuration = next.timestamp.timeIntervalSince(curr.timestamp).secondsToMinutes
                return curr.copyWith(duration: newDuration)
            } else {
                return curr
            }
        }

        return alignedTempBasals + (unifiedTempBasals.last.map { [$0] } ?? [])
    }

    /// Calculates periods of pump suspension using `PumpSuspend` and `PumpResume` events.
    ///
    /// The algorithm just looks at time intervals from suspend events to resume events to calculate
    /// periods of suspension.
    private static func getSuspends(
        pumpHistory: [ComputedPumpHistoryEvent],
        clock: Date
    ) throws -> [PumpSuspended] {
        let pumpSuspendResumeFull = pumpHistory.filter { $0.type == .pumpSuspend || $0.type == .pumpResume }

        // drop all repeated suspend / resume events to match JS
        let pumpSuspendResume = pumpSuspendResumeFull.reduce(into: [ComputedPumpHistoryEvent]()) { result, event in
            if result.last?.type != event.type {
                result.append(event)
            }
        }

        for (curr, next) in zip(pumpSuspendResume, pumpSuspendResume.dropFirst()) {
            guard curr.type != next.type, curr.timestamp != next.timestamp else {
                throw IobError.pumpSuspendResumeMismatch
            }
        }

        var suspends = zip(pumpSuspendResume, pumpSuspendResume.dropFirst()).compactMap { curr, next -> PumpSuspended? in
            if curr.type == .pumpResume {
                return nil
            } else {
                let duration = next.timestamp.timeIntervalSince(curr.timestamp).secondsToMinutes
                return PumpSuspended(timestamp: curr.timestamp, durationInMinutes: duration)
            }
        }

        // If our first suspend/resume event is a resume, the pump is suspended
        // when our history begins

        let maxPumpHistoryAgo = clock - TimeInterval(hours: MAX_PUMP_HISTORY_HOURS)
        if let first = pumpSuspendResume.first, first.type == .pumpResume, maxPumpHistoryAgo < first.timestamp {
            let start = maxPumpHistoryAgo
            let duration = first.timestamp.timeIntervalSince(start).secondsToMinutes
            suspends.append(PumpSuspended(timestamp: start, durationInMinutes: duration, isSuspendedPrior: true))
        }

        // if our last suspend/resume is a suspend, the pump is currently suspended
        if let last = pumpSuspendResume.last, last.type == .pumpSuspend {
            let duration = clock.timeIntervalSince(last.timestamp).secondsToMinutes
            suspends.append(PumpSuspended(timestamp: last.timestamp, durationInMinutes: duration, isCurrentlySuspended: true))
        }

        return suspends.sorted { $0.timestamp < $1.timestamp }
    }

    /// Modifies or removes tempBasals that overlap with suspension periods
    ///
    /// Truncate, move, or remove temp basal commands that overlap with suspension periods.
    ///
    /// This implementation matches the Javascript, which has some bugs. See this issue for details:
    /// https://github.com/nightscout/Trio-dev/issues/357
    private static func modifyTempBasalDuringSuspend(
        tempBasal: ComputedPumpHistoryEvent,
        suspends: [PumpSuspended]
    ) -> [ComputedPumpHistoryEvent] {
        guard let tempBasalDuration = tempBasal.duration, tempBasalDuration != 0 else {
            return [tempBasal]
        }

        for (index, suspend) in suspends.enumerated() {
            if suspend.doesOverlap(with: tempBasal) {
                let tempBasalStartsBeforeSuspend = tempBasal.timestamp < suspend.timestamp
                let tempBasalEnd = tempBasal.timestamp + tempBasalDuration.minutesToSeconds
                let tempBasalEndsAfterSuspend = tempBasalEnd > suspend.end

                switch (tempBasalStartsBeforeSuspend, tempBasalEndsAfterSuspend) {
                case (false, false):
                    // the temp basal is completely within the suspend
                    // just remove it, I think JS will give a negative duration
                    return []
                case (true, false):
                    // the temp basal starts first but ends during the suspend, truncate it
                    let newDuration = suspend.timestamp.timeIntervalSince(tempBasal.timestamp).secondsToMinutes
                    return [tempBasal.copyWith(duration: newDuration)]
                case (false, true):
                    // the temp basal starts during the suspend but goes on
                    // past, adjust the start date
                    let newDuration = tempBasalEnd.timeIntervalSince(suspend.end).secondsToMinutes
                    let newTempBasal = tempBasal.copyWith(
                        duration: newDuration,
                        timestamp: suspend.end
                    )
                    return modifyTempBasalDuringSuspend(tempBasal: newTempBasal, suspends: Array(suspends.dropFirst(index + 1)))
                case (true, true):
                    // the suspend is completely within the temp basal
                    // so we need to split the temp basal
                    let firstDuration = suspend.timestamp.timeIntervalSince(tempBasal.timestamp).secondsToMinutes
                    let firstTempBasal = tempBasal.copyWith(duration: firstDuration)
                    let secondDuration = tempBasalEnd.timeIntervalSince(suspend.end).secondsToMinutes
                    let secondTempBasal = tempBasal.copyWith(
                        duration: secondDuration,
                        timestamp: suspend.end,
                        omitFromTempHistory: true
                    )
                    return [firstTempBasal] +
                        modifyTempBasalDuringSuspend(tempBasal: secondTempBasal, suspends: Array(suspends.dropFirst(index + 1)))
                }
            }
        }

        return [tempBasal]
    }

    private static func adjustForCurrentlySuspended(
        tempBasals: [ComputedPumpHistoryEvent],
        suspends: [PumpSuspended]
    ) -> [ComputedPumpHistoryEvent] {
        guard let lastSuspend = suspends.last, lastSuspend.isCurrentlySuspended else {
            return tempBasals
        }

        return tempBasals
        // This logic in Javascript never runs because it's in an `if`
        // statement that compares a date (number) with a timestamp (string)
        // which will always evaluate to false.
        //
        // Although I think this logic is what the algorithm is trying
        // to do, this will get rid of zero duration temp, so I don't
        // think we should use it
        /*
         let lastSuspendTime = lastSuspend.timestamp
         return tempBasals.map { event in
             guard event.end > lastSuspendTime else {
                 return event
             }

             if event.timestamp > lastSuspendTime {
                 return event.copyWith(duration: 0)
             } else {
                 let newDuration = lastSuspendTime.timeIntervalSince(event.timestamp).secondsToMinutes
                 return event.copyWith(duration: newDuration)
             }
         }
         */
    }

    private static func adjustForSuspendedPrior(
        tempBasals: [ComputedPumpHistoryEvent],
        suspends: [PumpSuspended]
    ) -> [ComputedPumpHistoryEvent] {
        guard let firstSuspend = suspends.first, firstSuspend.isSuspendedPrior else {
            return tempBasals
        }

        let firstResumeDate = firstSuspend.end
        return tempBasals.map { event in
            let eventStartsBeforeResume = event.timestamp < firstResumeDate
            guard eventStartsBeforeResume else {
                return event
            }

            if event.end < firstResumeDate {
                return event.copyWith(duration: 0)
            } else {
                let newDuration = event.end.timeIntervalSince(firstResumeDate).secondsToMinutes
                return event.copyWith(duration: newDuration, timestamp: firstResumeDate)
            }
        }
    }

    /// Split up temp basals that overlap with suspends
    ///
    /// In Javascript, the algorithm mutates the original tempBasal and includes the mutated
    /// entry in the tempHistory that it returns. But, it omits any zero temp basals it injects
    /// or for temp basals that it splits into multiple parts it only includes the original temp basal
    /// in the temp history even though it accounts for these with the IoB calculation. To signify
    /// these entries that are just for accounting, we mark them as
    /// `omitFromTempHistory == true`.
    private static func splitAroundSuspends(
        tempBasals: [ComputedPumpHistoryEvent],
        suspends: [PumpSuspended]
    ) -> [ComputedPumpHistoryEvent] {
        var tempBasals = adjustForSuspendedPrior(tempBasals: tempBasals, suspends: suspends)
        tempBasals = adjustForCurrentlySuspended(tempBasals: tempBasals, suspends: suspends)
        tempBasals = tempBasals.flatMap { modifyTempBasalDuringSuspend(tempBasal: $0, suspends: suspends) }
        let zeroTempBasals = suspends
            .map {
                ComputedPumpHistoryEvent
                    .zeroTempBasal(timestamp: $0.timestamp, duration: $0.durationInMinutes, omitFromTempHistory: true) }

        return (tempBasals + zeroTempBasals).sorted { $0.timestamp < $1.timestamp
        }
    }

    private static func splitAtMinutesSinceMidnight(
        tempBasal: ComputedPumpHistoryEvent,
        splitPoint: Decimal
    ) throws -> [ComputedPumpHistoryEvent] {
        // FIXME: bug in JS where they only use minute precision for startMinutes
        // The net effect is that it truncates the startMinutes. The differences should
        // be small but at least it matches
        // the fix it to use minutesSinceMidnightWithPrecision
        guard let startMinutes = tempBasal.timestamp.minutesSinceMidnight.map({ Decimal($0) }) else {
            throw CalendarError.invalidCalendar
        }

        guard let duration = tempBasal.duration else {
            throw IobError.tempBasalDurationMissingDuration(timestamp: tempBasal.timestamp)
        }

        let event1Duration = splitPoint - startMinutes
        let event2Duration = duration - event1Duration
        let event2Start = tempBasal.timestamp + event1Duration.minutesToSeconds

        return [
            tempBasal.copyWith(duration: event1Duration),
            tempBasal.copyWith(duration: event2Duration, timestamp: event2Start)
        ]
    }

    private static func splitAtProfileBreak(
        tempBasal: ComputedPumpHistoryEvent,
        profileBreaks: [Decimal]
    ) throws -> [ComputedPumpHistoryEvent] {
        guard let duration = tempBasal.duration else {
            throw IobError.tempBasalMissingDuration(timestamp: tempBasal.timestamp)
        }

        guard let startMinutes = tempBasal.timestamp.minutesSinceMidnightWithPrecision else {
            throw CalendarError.invalidCalendar
        }

        let endMinutes = startMinutes + duration
        for profileBreak in profileBreaks {
            if profileBreak > startMinutes, profileBreak < endMinutes {
                return try splitAtMinutesSinceMidnight(tempBasal: tempBasal, splitPoint: profileBreak)
            }
        }

        return [tempBasal]
    }

    // we know that these are all at most 30 minutes since we split by 30m first
    private static func splitAtMidnight(tempBasal: ComputedPumpHistoryEvent) throws -> [ComputedPumpHistoryEvent] {
        let minutesPerDay = Decimal(24 * 60)
        guard let startMinutes = tempBasal.timestamp.minutesSinceMidnightWithPrecision else {
            throw CalendarError.invalidCalendar
        }

        guard let duration = tempBasal.duration else {
            throw IobError.tempBasalMissingDuration(timestamp: tempBasal.timestamp)
        }

        let endMinutes = startMinutes + duration
        if endMinutes > minutesPerDay {
            return try splitAtMinutesSinceMidnight(tempBasal: tempBasal, splitPoint: minutesPerDay)
        } else {
            return [tempBasal]
        }
    }

    private static func splitBy30mDuration(tempBasal: ComputedPumpHistoryEvent) throws -> [ComputedPumpHistoryEvent] {
        guard let duration = tempBasal.duration else {
            throw IobError.tempBasalMissingDuration(timestamp: tempBasal.timestamp)
        }

        return stride(from: tempBasal.timestamp, to: tempBasal.timestamp + duration.minutesToSeconds, by: 30.minutesToSeconds)
            .map { start in

                // Calculate the duration for this chunk
                let endOfChunk = start + 30.minutesToSeconds
                let endOfTempBasal = tempBasal.timestamp + duration.minutesToSeconds
                let end = min(endOfChunk, endOfTempBasal)
                let durationInSeconds = end.timeIntervalSince(start)

                return tempBasal.copyWith(duration: durationInSeconds.secondsToMinutes, timestamp: start)
            }
    }

    /// Splits any temp basal commands that cross profile break points to simplify the IoB calculation
    private static func splitTempBasal(
        tempBasal: ComputedPumpHistoryEvent,
        profileBreaks: [Decimal]
    ) throws -> [ComputedPumpHistoryEvent] {
        try splitBy30mDuration(tempBasal: tempBasal)
            .flatMap({ try splitAtMidnight(tempBasal: $0) })
            .flatMap({ try splitAtProfileBreak(tempBasal: $0, profileBreaks: profileBreaks) })
    }

    /// Converts tempBasal commands to bolus commands with roughly equal insulin delivered
    private static func extractTempBoluses(
        from tempBasal: ComputedPumpHistoryEvent,
        profile: Profile,
        autosens: Autosens?
    ) throws -> [ComputedPumpHistoryEvent] {
        guard let duration = tempBasal.duration, duration > 0 else {
            return []
        }

        guard let tempBasalRate = tempBasal.rate else {
            throw IobError.rateNotSetOnTempBasal(timestamp: tempBasal.timestamp)
        }

        guard let profileCurrentRate = try Basal.basalLookup(profile.basalprofile ?? [], now: tempBasal.timestamp) ?? profile
            .currentBasal
        else {
            throw IobError.basalRateNotSet
        }

        let currentRate = autosens.map { $0.ratio * profileCurrentRate } ?? profileCurrentRate

        let netBasalRate = tempBasalRate - currentRate
        let tempBolusSize: Decimal = netBasalRate < 0 ? -0.05 : 0.05

        let netBasalAmountTmp = (netBasalRate * duration * 10 / 6).jsRounded()
        let netBasalAmount = netBasalAmountTmp / Decimal(100)
        // FIXME: I think the count should be floor not rounded due to pump implementation artifacts
        let tempBolusCount = Int((netBasalAmount / tempBolusSize).rounded())

        let tempBolusSpacing = Decimal(duration.minutesToSeconds) / Decimal(tempBolusCount)

        return (0 ..< tempBolusCount).map { j in
            let timestamp = tempBasal.timestamp + Double(j) * Double(tempBolusSpacing)
            return ComputedPumpHistoryEvent.tempBolus(timestamp: timestamp, insulin: tempBolusSize)
        }
    }

    /// Converts tempBasal commands into a series of relative bolus amounts.
    ///
    /// Operates on net insulin delivery relative to the current basal rate. Can result in
    /// negative bolus amounts.
    private static func convertTempBasalToBolus(
        tempHistory: [ComputedPumpHistoryEvent],
        profile: Profile,
        autosens: Autosens?
    ) throws -> [ComputedPumpHistoryEvent] {
        let profileBreaksMinutesSinceMidnight = profile.basalprofile?.map({ Decimal($0.minutes) }) ?? []
        let splitTempBasals = try tempHistory
            .flatMap { try splitTempBasal(tempBasal: $0, profileBreaks: profileBreaksMinutesSinceMidnight) }
        return try splitTempBasals
            .flatMap { try extractTempBoluses(from: $0, profile: profile, autosens: autosens) }
    }

    static func calcTempTreatments(
        history: [ComputedPumpHistoryEvent],
        profile: Profile,
        clock: Date,
        autosens: Autosens?,
        zeroTempDuration: Decimal?
    ) throws -> [ComputedPumpHistoryEvent] {
        // ignore any records in the future and sort them
        let pumpHistory = history.filter({ $0.timestamp <= clock }).sorted { $0.timestamp < $1.timestamp }
        let tempBasals = try getTempBasals(pumpHistory: pumpHistory, clock: clock, zeroTempDuration: zeroTempDuration)
        let suspends = try getSuspends(pumpHistory: pumpHistory, clock: clock)
        let boluses = pumpHistory.filter({ $0.type == .bolus }).map { $0.copyWith(insulin: $0.amount) }

        var tempHistory: [ComputedPumpHistoryEvent]
        if profile.suspendZerosIob {
            tempHistory = splitAroundSuspends(tempBasals: tempBasals, suspends: suspends)
        } else {
            tempHistory = tempBasals
        }

        let tempBoluses = try convertTempBasalToBolus(
            tempHistory: tempHistory,
            profile: profile,
            autosens: autosens
        )

        tempHistory = tempHistory.filter { !$0.omitFromTempHistory }

        return (boluses + tempBoluses + tempHistory).sorted { $0.timestamp < $1.timestamp }
    }
}
