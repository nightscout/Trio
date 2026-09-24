import Foundation

/// Infers scheduled-basal delivery for spans no pump event covers (open loop,
/// connectivity loss). Pure timeline sweep computed on demand; nothing is persisted.
enum ScheduledBasalInference {
    struct Segment: Equatable {
        let start: Date
        let end: Date
        let rate: Decimal
    }

    struct TimelineEvent {
        enum Kind {
            case tempBasal
            case suspend
            case resume
            case profileRateChange
            case now
        }

        let start: Date
        let end: Date
        let kind: Kind

        // point events (suspend, resume, profileRateChange, now) have start == end
        init(start: Date, end: Date? = nil, kind: Kind) {
            self.start = start
            self.end = max(start, end ?? start)
            self.kind = kind
        }
    }

    static let minGapSeconds: TimeInterval = 60

    /// `events`: real pump events only; profileRateChange and now events are added here. Never
    /// fabricates before the first event, after `now`, or while suspended.
    static func segments(
        events: [TimelineEvent],
        profile: [BasalProfileEntry],
        now: Date,
        minGapSeconds: TimeInterval = minGapSeconds
    ) -> [Segment] {
        guard !profile.isEmpty,
              let firstStart = events.map(\.start).min(),
              firstStart < now
        else { return [] }

        var timeline = events
        timeline += profileRateChangeEvents(from: firstStart, to: now, profile: profile)
        timeline.append(TimelineEvent(start: now, kind: .now))
        timeline.sort { $0.start < $1.start }

        // a resume with no earlier suspend means the pump entered the window suspended
        var suspended = timeline
            .first(where: { $0.kind == .suspend || $0.kind == .resume })?.kind == .resume

        var segments: [Segment] = []
        // overlap guard: a gap opens only past everything already covered
        var coveredUntil = firstStart

        for (curr, next) in zip(timeline, timeline.dropFirst()) {
            switch curr.kind {
            case .suspend: suspended = true
            case .resume: suspended = false
            default: break
            }
            coveredUntil = max(coveredUntil, curr.end)

            guard !suspended, next.start.timeIntervalSince(coveredUntil) >= minGapSeconds else { continue }
            guard let rate = findBasalRateForOffset(for: minutesOfDay(coveredUntil), in: profile) else { continue }

            segments.append(Segment(start: coveredUntil, end: next.start, rate: rate))
        }
        return segments
    }

    /// Splits gaps at basal schedule boundaries so each segment carries one rate.
    private static func profileRateChangeEvents(
        from start: Date,
        to end: Date,
        profile: [BasalProfileEntry]
    ) -> [TimelineEvent] {
        let calendar = Calendar.current
        var rateChanges: [TimelineEvent] = []
        var day = calendar.startOfDay(for: start)

        while day < end {
            for minutes in profile.map(\.minutes) {
                // wall-clock boundary; adding seconds to startOfDay drifts on DST days
                guard let boundary = calendar.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: day
                ) else { continue }
                if boundary > start, boundary < end {
                    rateChanges.append(TimelineEvent(start: boundary, kind: .profileRateChange))
                }
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return rateChanges
    }

    private static func minutesOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

// MARK: - Delivery at an instant

extension ScheduledBasalInference {
    /// What the pump is delivering at one point in time.
    enum Delivery: Equatable {
        case suspended
        case temp(Decimal)
        case scheduled(Decimal)
    }

    /// A basal event from pump history; a schedule report has `end == start`.
    struct BasalEvent {
        let start: Date
        let end: Date
        let rate: Decimal
        let isScheduled: Bool
    }

    /// Resolves delivery at `now`; `events` and `suspensions` are ascending.
    static func delivery(
        events: [BasalEvent],
        suspensions: [(date: Date, isSuspend: Bool)],
        profile: [BasalProfileEntry],
        now: Date
    ) -> Delivery? {
        let lastSuspension = suspensions.last { $0.date <= now }
        if lastSuspension?.isSuspend == true { return .suspended }

        // a resume hands delivery back to the schedule, whatever the temp claimed
        let resumedAt = lastSuspension?.date ?? .distantPast

        if let current = events.last(where: { $0.start <= now }),
           !current.isScheduled,
           current.start >= resumedAt,
           current.end > now
        {
            return .temp(current.rate)
        }

        guard let rate = findBasalRateForOffset(for: minutesOfDay(now), in: profile) else { return nil }
        return .scheduled(rate)
    }
}
