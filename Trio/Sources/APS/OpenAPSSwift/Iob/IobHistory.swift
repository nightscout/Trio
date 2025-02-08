import Foundation

/// The Javascript implementation was too complex to port directly, so this is a clean implementation
/// of the original logic. There are a few differences:
///  - We are more strict in error checking
///  - We ignore event types that Trio won't send us
///  - We exclude some redundant events (shouldn't impact the IoB calculation)
///
///  There are two areas where we changed the implementation that could impact IoB calculations
///  - We don't split temp basals that cross suspends -- after a suspend resumes we assume that
///     it goes back to the profile basal rate
///  - We don't split temp basals into 30 minute durations. This doesn't impact the total insulin accounting
///    but could give the temp basal bolus entries slightly different timing
///
///  From looking at the implementat, the `suspendZerosIob` should just be on by default to
///  handle pump suspensions correctly

struct IobHistory {
    struct PumpSuspended {
        let timestamp: Date
        let durationInMinutes: Decimal

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
            duration: zeroTempDuration ?? 0
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
    private static func getSuspends(pumpHistory: [ComputedPumpHistoryEvent], clock: Date) throws -> [PumpSuspended] {
        let pumpSuspendResume = pumpHistory.filter { $0.type == .pumpSuspend || $0.type == .pumpResume }

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

        if let last = pumpSuspendResume.last, last.type == .pumpSuspend {
            let duration = (clock + 1.minutesToSeconds).timeIntervalSince(last.timestamp).secondsToMinutes
            suspends.append(PumpSuspended(timestamp: last.timestamp, durationInMinutes: duration))
        }

        return suspends
    }

    /// Modifies or removes tempBasals that overlap with suspension periods
    ///
    /// Truncate, move, or remove temp basal commands that overlap with suspension periods.
    ///
    /// **Difference from Javascript**
    /// One important note is that once a suspend happens, the pump doesn't go back to the temp basal's rate
    /// (at least the omnipod doesn't). When you resume, it resumes at the scheduled basal rate and stays
    /// there until you issue a new TempBasal command. Thus, we don't split `TempBasal` entries when
    /// a suspend starts in the middle, we truncate them, which is different from the Javascript implementation.
    ///
    /// Dealing with `TempBasal` records that start while the pump is suspended is a bit more nuanced becase
    /// theoretically this sholdn't be possible. For this case, we follow the Javascript implementation and
    /// move the `TempBasal` to start after the resume happens.
    ///
    /// Finally it adds zero temp basal events for the suspend periods for the IoB calculation
    private static func modifyTempBasalDuringSuspend(
        tempBasal: ComputedPumpHistoryEvent,
        suspends: [PumpSuspended]
    ) -> ComputedPumpHistoryEvent? {
        for suspend in suspends {
            if suspend.doesOverlap(with: tempBasal) {
                let tempBasalEnd = tempBasal.timestamp + (tempBasal.duration ?? 0).minutesToSeconds
                if tempBasal.timestamp <= suspend.timestamp {
                    // truncate if the suspend starts during the temp basal
                    let duration = suspend.timestamp.timeIntervalSince(tempBasal.timestamp).secondsToMinutes
                    return tempBasal.copyWith(duration: duration)
                } else if tempBasalEnd <= suspend.end {
                    // tempBasal is completely within the suspend
                    return nil
                } else {
                    // adjust start and duration to start after suspend ends
                    let duration = tempBasalEnd.timeIntervalSince(suspend.end).secondsToMinutes
                    return tempBasal.copyWith(duration: duration, timestamp: suspend.end)
                }
            }
        }

        return tempBasal
    }

    private static func splitAroundSuspends(
        tempBasals: [ComputedPumpHistoryEvent],
        suspends: [PumpSuspended]
    ) -> [ComputedPumpHistoryEvent] {
        let tempBasals = tempBasals.compactMap { modifyTempBasalDuringSuspend(tempBasal: $0, suspends: suspends) }
        let zeroTempBasals = suspends
            .map { ComputedPumpHistoryEvent.zeroTempBasal(timestamp: $0.timestamp, duration: $0.durationInMinutes) }

        let tempHistory = (tempBasals + zeroTempBasals).sorted { $0.timestamp < $1.timestamp
        }

        let adjustedTempHistory = zip(tempHistory, tempHistory.dropFirst()).map { curr, next in
            let end = curr.timestamp + (curr.duration ?? 0).minutesToSeconds
            if end > next.timestamp {
                let newDuration = next.timestamp.timeIntervalSince(end).secondsToMinutes
                return curr.copyWith(duration: newDuration)
            } else {
                return curr
            }
        }

        return adjustedTempHistory + (tempHistory.last.map { [$0] } ?? [])
    }

    /// Returns the relative offset of a profile break in the middle of the event, if one exists
    private static func findIntersectionOffset(tempBasal: ComputedPumpHistoryEvent, profileBreaks: [Decimal]) -> TimeInterval? {
        let minutesPerDay = Decimal(24 * 60)
        if let minutes = tempBasal.timestamp.minutesSinceMidnightWithPrecision {
            let endMinutes = minutes + (tempBasal.duration ?? 0)
            for profileBreak in profileBreaks {
                let breakPlusOneDay = profileBreak + minutesPerDay
                if profileBreak > minutes, profileBreak < endMinutes {
                    return (profileBreak - minutes).minutesToSeconds
                } else if breakPlusOneDay > minutes, breakPlusOneDay < endMinutes {
                    return (breakPlusOneDay - minutes).minutesToSeconds
                }
            }
        }

        return nil
    }

    /// Splits any temp basal commands that cross profile break points to simplify the IoB calculation
    private static func splitTempBasal(
        tempBasal: ComputedPumpHistoryEvent,
        profileBreaks: [Decimal],
        accumulator: [ComputedPumpHistoryEvent] = []
    ) -> [ComputedPumpHistoryEvent] {
        guard let offset = findIntersectionOffset(tempBasal: tempBasal, profileBreaks: profileBreaks),
              let duration = tempBasal.duration
        else {
            return accumulator + [tempBasal]
        }

        let firstEvent = tempBasal.copyWith(duration: offset.secondsToMinutes)
        let secondEvent = tempBasal.copyWith(
            duration: duration - offset.secondsToMinutes,
            timestamp: tempBasal.timestamp + offset
        )

        // use tail recursion to give the compiler a chance to optimize
        return splitTempBasal(tempBasal: secondEvent, profileBreaks: profileBreaks, accumulator: accumulator + [firstEvent])
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

        let netBasalAmountTmp = (netBasalRate * duration * 10 / 6).rounded()
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
        let splitTempBasals = tempHistory
            .flatMap { splitTempBasal(tempBasal: $0, profileBreaks: profileBreaksMinutesSinceMidnight) }

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

        let tempHistory: [ComputedPumpHistoryEvent]
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

        return (boluses + tempBoluses + tempHistory).sorted { $0.timestamp < $1.timestamp }
    }
}
