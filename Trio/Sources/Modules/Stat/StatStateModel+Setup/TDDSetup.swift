import CoreData
import Foundation

struct TDDStats: Identifiable {
    var id: Date { date }
    let date: Date
    let amount: Double
}

extension Stat.StateModel {
    func setupTDDStats() {
        Task {
            do {
                let (hourly, daily) = try await fetchTDDStats()

                await MainActor.run {
                    self.hourlyTDDStats = hourly
                    self.dailyTDDStats = daily
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed fetching TDD stats: \(error)")
            }
        }
    }

    private func fetchTDDStats() async throws -> (hourly: [TDDStats], daily: [TDDStats]) {
        let tddTaskContext = CoreDataStack.shared.newTaskContext()
        tddTaskContext.name = "StatStateModel.fetchTDDStats"

        let tddResults = try await fetchTDDStoredRecords(on: tddTaskContext)

        let (
            bolusResults,
            tempBasalResults,
            suspendEvents,
            resumeEvents
        ) = try await fetchHourlyInsulinRecords(on: tddTaskContext)

        var hourlyStats: [TDDStats] = []
        var dailyStats: [TDDStats] = []

        await tddTaskContext.perform {
            let calendar = Calendar.current

            if let fetchedTDDs = tddResults as? [TDDStored] {
                dailyStats = Self.processDailyTDDs(fetchedTDDs, calendar: calendar)
            }

            if let fetchedBoluses = bolusResults as? [BolusStored],
               let fetchedTempBasals = tempBasalResults as? [TempBasalStored],
               let fetchedSuspendEvents = suspendEvents as? [PumpEventStored],
               let fetchedResumeEvents = resumeEvents as? [PumpEventStored]
            {
                hourlyStats = Self.processHourlyInsulinData(
                    boluses: fetchedBoluses,
                    tempBasals: fetchedTempBasals,
                    suspendEvents: fetchedSuspendEvents,
                    resumeEvents: fetchedResumeEvents,
                    calendar: calendar
                )
            }
        }

        return (hourlyStats, dailyStats)
    }

    private func fetchTDDStoredRecords(on tddTaskContext: NSManagedObjectContext) async throws -> Any {
        let threeMonthsAgo = Date().addingTimeInterval(-3.months.timeInterval)
        let predicate = NSPredicate(format: "date >= %@", threeMonthsAgo as NSDate)

        return try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: tddTaskContext,
            predicate: predicate,
            key: "date",
            ascending: true,
            batchSize: 100
        )
    }

    private func fetchHourlyInsulinRecords(on tddTaskContext: NSManagedObjectContext) async throws
        -> (bolus: Any, tempBasal: Any, suspendEvents: Any, resumeEvents: Any)
    {
        let now = Date()
        let twentyDaysAgo = calendar.date(byAdding: .day, value: -StatChartUtils.hourlyWindowDays, to: now)!

        let datePredicate = NSPredicate(
            format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
            twentyDaysAgo as NSDate,
            now as NSDate
        )

        let bolusResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: BolusStored.self,
            onContext: tddTaskContext,
            predicate: datePredicate,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        let tempBasalResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempBasalStored.self,
            onContext: tddTaskContext,
            predicate: datePredicate,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        let suspendResumeTypes = [
            PumpEventStored.EventType.pumpSuspend.rawValue,
            PumpEventStored.EventType.pumpResume.rawValue
        ]

        let suspendResumePredicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@ AND type IN %@",
            twentyDaysAgo as NSDate,
            now as NSDate,
            suspendResumeTypes
        )

        let suspendResumeResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: tddTaskContext,
            predicate: suspendResumePredicate,
            key: "timestamp",
            ascending: true,
            batchSize: 100
        )

        let (suspendEvents, resumeEvents) = await tddTaskContext.perform {
            var suspendEventsArray: [PumpEventStored] = []
            var resumeEventsArray: [PumpEventStored] = []

            if let pumpEvents = suspendResumeResults as? [PumpEventStored] {
                for event in pumpEvents {
                    if event.type == PumpEventStored.EventType.pumpSuspend.rawValue {
                        suspendEventsArray.append(event)
                    } else if event.type == PumpEventStored.EventType.pumpResume.rawValue {
                        resumeEventsArray.append(event)
                    }
                }
            }

            return (suspendEventsArray, resumeEventsArray)
        }

        return (bolusResults, tempBasalResults, suspendEvents, resumeEvents)
    }

    private static func processHourlyInsulinData(
        boluses: [BolusStored],
        tempBasals: [TempBasalStored],
        suspendEvents: [PumpEventStored],
        resumeEvents: [PumpEventStored],
        calendar: Calendar
    ) -> [TDDStats] {
        var insulinByHour: [Date: Double] = [:]

        for bolus in boluses {
            guard let timestamp = bolus.pumpEvent?.timestamp,
                  let amount = bolus.amount?.doubleValue
            else {
                continue
            }

            let components = calendar.dateComponents([.year, .month, .day, .hour], from: timestamp)
            guard let hourDate = calendar.date(from: components) else { continue }

            insulinByHour[hourDate, default: 0] += amount
        }

        let suspendResumePairs = Self.createSuspendResumePairs(suspendEvents: suspendEvents, resumeEvents: resumeEvents)

        let sortedTempBasals = tempBasals.sorted {
            ($0.pumpEvent?.timestamp ?? Date.distantPast) < ($1.pumpEvent?.timestamp ?? Date.distantPast)
        }

        for (index, tempBasal) in sortedTempBasals.enumerated() {
            guard let timestamp = tempBasal.pumpEvent?.timestamp,
                  let rate = tempBasal.rate?.doubleValue
            else {
                continue
            }

            var actualDurationInMinutes: Double

            // A new temp basal cancels the previous one, so duration runs until the next event.
            if index < sortedTempBasals.count - 1 {
                if let nextTimestamp = sortedTempBasals[index + 1].pumpEvent?.timestamp {
                    actualDurationInMinutes = nextTimestamp.timeIntervalSince(timestamp) / 60.0
                } else {
                    actualDurationInMinutes = Double(tempBasal.duration)
                }
            } else {
                actualDurationInMinutes = Double(tempBasal.duration)
            }

            let durationInHours = actualDurationInMinutes / 60.0

            // Delivered total already excludes suspensions and quantization, so spread it over unsuspended time.
            let unsuspendedHours = Self.calculateEffectiveDuration(
                from: timestamp,
                to: timestamp.addingTimeInterval(durationInHours * 3600),
                suspendResumePairs: suspendResumePairs
            )
            var effectiveRate = rate
            if let delivered = tempBasal.deliveredUnits?.doubleValue, unsuspendedHours > 0 {
                effectiveRate = delivered / unsuspendedHours
            }

            Self.distributeInsulinAcrossHours(
                startTime: timestamp,
                durationInHours: durationInHours,
                rate: effectiveRate,
                suspendResumePairs: suspendResumePairs,
                insulinByHour: &insulinByHour,
                calendar: calendar
            )
        }

        return insulinByHour.keys.sorted().map { hourDate in
            TDDStats(
                date: hourDate,
                amount: insulinByHour[hourDate, default: 0]
            )
        }
    }

    // Suspends with no resume yet are dropped.
    private static func createSuspendResumePairs(
        suspendEvents: [PumpEventStored],
        resumeEvents: [PumpEventStored]
    ) -> [(suspend: PumpEventStored, resume: PumpEventStored)] {
        let sortedSuspendEvents = suspendEvents.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        let sortedResumeEvents = resumeEvents.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }

        var pairs: [(suspend: PumpEventStored, resume: PumpEventStored)] = []

        for suspendEvent in sortedSuspendEvents {
            guard let suspendTime = suspendEvent.timestamp else { continue }

            if let resumeEvent = sortedResumeEvents.first(where: {
                guard let resumeTime = $0.timestamp else { return false }
                return resumeTime > suspendTime
            }) {
                pairs.append((suspend: suspendEvent, resume: resumeEvent))
            }
        }

        return pairs
    }

    private static func distributeInsulinAcrossHours(
        startTime: Date,
        durationInHours: Double,
        rate: Double,
        suspendResumePairs: [(suspend: PumpEventStored, resume: PumpEventStored)],
        insulinByHour: inout [Date: Double],
        calendar: Calendar
    ) {
        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: startTime)

        guard let startHourDate = calendar
            .date(from: calendar.dateComponents([.year, .month, .day, .hour], from: startTime))
        else {
            return
        }

        let minutesInFirstHour = 60.0 - Double(startComponents.minute ?? 0) - (Double(startComponents.second ?? 0) / 60.0)

        let hoursInFirstHour = min(durationInHours, minutesInFirstHour / 60.0)

        if hoursInFirstHour > 0 {
            let firstHourEndTime = startTime.addingTimeInterval(hoursInFirstHour * 3600)

            let effectiveDuration = calculateEffectiveDuration(
                from: startTime,
                to: firstHourEndTime,
                suspendResumePairs: suspendResumePairs
            )

            insulinByHour[startHourDate, default: 0] += rate * effectiveDuration
        }

        var remainingDuration = durationInHours - hoursInFirstHour

        var currentHourDate = calendar.date(byAdding: .hour, value: 1, to: startHourDate) ?? startHourDate

        while remainingDuration > 0 {
            let hoursToAdd = min(remainingDuration, 1.0)

            let hourStartTime = calendar
                .date(from: calendar.dateComponents([.year, .month, .day, .hour], from: currentHourDate)) ?? currentHourDate
            let hourEndTime = hourStartTime.addingTimeInterval(hoursToAdd * 3600)

            let effectiveDuration = calculateEffectiveDuration(
                from: hourStartTime,
                to: hourEndTime,
                suspendResumePairs: suspendResumePairs
            )

            insulinByHour[currentHourDate, default: 0] += rate * effectiveDuration

            remainingDuration -= hoursToAdd
            currentHourDate = calendar.date(byAdding: .hour, value: 1, to: currentHourDate) ?? currentHourDate
        }
    }

    private static func calculateEffectiveDuration(
        from startTime: Date,
        to endTime: Date,
        suspendResumePairs: [(suspend: PumpEventStored, resume: PumpEventStored)]
    ) -> Double {
        let totalDuration = endTime.timeIntervalSince(startTime) / 3600.0

        var suspendedDuration = 0.0

        for pair in suspendResumePairs {
            guard let suspendTime = pair.suspend.timestamp,
                  let resumeTime = pair.resume.timestamp
            else {
                continue
            }

            if suspendTime < endTime, resumeTime > startTime {
                let overlapStart = max(startTime, suspendTime)
                let overlapEnd = min(endTime, resumeTime)

                suspendedDuration += overlapEnd.timeIntervalSince(overlapStart) / 3600.0
            }
        }

        return max(0.0, totalDuration - suspendedDuration)
    }

    private static func makeTDDStats(date: Date, entries: [(date: Date, entry: TDDStored)]) -> TDDStats {
        let lastEntry = entries.max { $0.date < $1.date }

        return TDDStats(date: date, amount: lastEntry?.entry.total?.doubleValue ?? 0.0)
    }

    // TDD rows accumulate through the day, so the last entry is the day's total.
    private static func processDailyTDDs(_ tdds: [TDDStored], calendar: Calendar) -> [TDDStats] {
        let validEntries = tdds.compactMap { entry -> (date: Date, entry: TDDStored)? in
            guard let date = entry.date else { return nil }
            return (date, entry)
        }

        let dailyGrouped = Dictionary(grouping: validEntries) { calendar.startOfDay(for: $0.date) }

        return dailyGrouped.sorted { $0.key < $1.key }.map {
            Self.makeTDDStats(date: $0.key, entries: $0.value)
        }
    }

    func calculateTDDAverages(for range: (start: Date, end: Date)) -> Double {
        let relevantStats = dailyTDDStats.filter { stat in
            StatChartUtils.isStatInRange(
                calendar.startOfDay(for: stat.date),
                in: range
            )
        }

        guard !relevantStats.isEmpty else { return 0.0 }

        let sums = relevantStats.reduce(0.0) { acc, day in
            acc + day.amount
        }
        let count = Double(relevantStats.count)

        return sums / count
    }

    func calculateTDDTotals(for range: (start: Date, end: Date)) -> Double {
        let relevantStats = hourlyTDDStats.filter { stat in
            StatChartUtils.isStatInRange(
                stat.date,
                in: range
            )
        }

        let sums = relevantStats.reduce(0.0) { acc, hour in
            acc + hour.amount
        }

        return sums
    }
}
