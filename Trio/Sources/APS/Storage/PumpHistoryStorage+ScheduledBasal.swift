import CoreData
import Foundation

/// Synthesizes scheduled-basal records for gaps no pump reports (open loop,
/// connectivity loss). Reported data always wins: overlapping synthetic rows
/// are deleted each run. Rows are flagged `isScheduledBasal` and excluded
/// from oref input, uploads, and TBR consumers.
extension BasePumpHistoryStorage {
    private enum ReconcilerConfig {
        static let lookbackHours: Double = 24
        static let minGapSeconds: TimeInterval = 60
        static let identifierPrefix = "trio-sbr-"
    }

    func reconcileScheduledBasal() async throws {
        try await reconcileScheduledBasal(now: Date())
    }

    func reconcileScheduledBasal(now: Date) async throws {
        guard let profile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self),
              !profile.isEmpty
        else { return }

        try await context.perform {
            let windowStart = now.addingTimeInterval(-ReconcilerConfig.lookbackHours * 3600)

            let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
            request.predicate = NSPredicate(format: "timestamp >= %@", windowStart as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            let events = try self.context.fetch(request)

            // never fabricate history before the first reported event
            guard let firstEventDate = events.first?.timestamp else { return }
            let fillStart = max(windowStart, firstEventDate)

            var covered: [DateInterval] = []
            var openSuspendStart: Date?
            for event in events {
                switch event.type {
                case PumpEvent.tempBasal.rawValue:
                    guard let temp = event.tempBasal, !temp.isScheduledBasal else { continue }
                    let start = temp.startDate ?? event.timestamp ?? now
                    let end = temp.endDate ?? start.addingTimeInterval(TimeInterval(temp.duration) * 60)
                    if end > start { covered.append(DateInterval(start: start, end: end)) }
                case PumpEvent.pumpSuspend.rawValue:
                    openSuspendStart = openSuspendStart ?? event.timestamp
                case PumpEvent.pumpResume.rawValue:
                    if let suspendStart = openSuspendStart, let resumeDate = event.timestamp, resumeDate > suspendStart {
                        covered.append(DateInterval(start: suspendStart, end: resumeDate))
                        openSuspendStart = nil
                    }
                default:
                    break
                }
            }
            if let suspendStart = openSuspendStart, suspendStart < now {
                covered.append(DateInterval(start: suspendStart, end: now))
            }
            let reported = Self.merged(covered)

            // mutable tail is recomputed each run; overlaps yield to reported data
            var keptSynthetic: [DateInterval] = []
            for event in events {
                guard let temp = event.tempBasal, temp.isScheduledBasal else { continue }
                let start = temp.startDate ?? event.timestamp ?? now
                let end = max(start, temp.endDate ?? start)
                let interval = DateInterval(start: start, end: end)
                if event.isMutable || reported.contains(where: { ($0.intersection(with: interval)?.duration ?? 0) > 0 }) {
                    self.context.delete(event)
                } else {
                    keptSynthetic.append(interval)
                }
            }

            let blocked = Self.merged(reported + keptSynthetic)
            let gaps = Self.gaps(in: DateInterval(start: fillStart, end: now), excluding: blocked)
                .filter { $0.duration >= ReconcilerConfig.minGapSeconds }

            for gap in gaps {
                for segment in Self.scheduleSegments(for: gap, profile: profile) {
                    let isTrailing = abs(segment.end.timeIntervalSince(now)) < 1
                    self.insertScheduledBasal(segment, profile: profile, isMutable: isTrailing)
                }
            }

            guard self.context.hasChanges else { return }
            try self.context.save()
            self.updateSubject.send(())
        }
    }

    private func insertScheduledBasal(_ interval: DateInterval, profile: [BasalProfileEntry], isMutable: Bool) {
        let rate = findBasalRateForOffset(for: Self.minutesOfDay(interval.start), in: profile) ?? 0

        let newPumpEvent = PumpEventStored(context: context)
        newPumpEvent.id = UUID().uuidString
        newPumpEvent.timestamp = interval.start
        newPumpEvent.type = PumpEvent.tempBasal.rawValue
        newPumpEvent.syncIdentifier = ReconcilerConfig.identifierPrefix + UUID().uuidString
        newPumpEvent.isMutable = isMutable
        // bookkeeping rows never upload
        newPumpEvent.isUploadedToNS = true
        newPumpEvent.isUploadedToHealth = true
        newPumpEvent.isUploadedToTidepool = true

        let newTempBasal = TempBasalStored(context: context)
        newTempBasal.pumpEvent = newPumpEvent
        newTempBasal.isScheduledBasal = true
        newTempBasal.rate = rate as NSDecimalNumber
        newTempBasal.startDate = interval.start
        newTempBasal.endDate = interval.end
        newTempBasal.duration = Int16(round(interval.duration / 60))
        newTempBasal.tempType = TempType.absolute.rawValue
    }

    // MARK: - Interval math

    private static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                if interval.end > last.end {
                    result[result.count - 1] = DateInterval(start: last.start, end: interval.end)
                }
            } else {
                result.append(interval)
            }
        }
        return result
    }

    private static func gaps(in window: DateInterval, excluding blocked: [DateInterval]) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var cursor = window.start
        for interval in blocked where interval.end > window.start && interval.start < window.end {
            if interval.start > cursor {
                gaps.append(DateInterval(start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < window.end {
            gaps.append(DateInterval(start: cursor, end: window.end))
        }
        return gaps
    }

    /// Splits a gap at basal schedule boundaries so each row carries one rate.
    private static func scheduleSegments(for gap: DateInterval, profile: [BasalProfileEntry]) -> [DateInterval] {
        var segments: [DateInterval] = []
        var cursor = gap.start
        while cursor < gap.end {
            let boundary = nextScheduleBoundary(after: cursor, profile: profile)
            let end = min(boundary, gap.end)
            segments.append(DateInterval(start: cursor, end: end))
            cursor = end
        }
        return segments
    }

    private static func nextScheduleBoundary(after date: Date, profile: [BasalProfileEntry]) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let minutes = minutesOfDay(date)
        if let next = profile.map(\.minutes).sorted().first(where: { $0 > minutes }) {
            return startOfDay.addingTimeInterval(TimeInterval(next * 60))
        }
        // next boundary is the following midnight
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date.addingTimeInterval(24 * 3600)
    }

    private static func minutesOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
