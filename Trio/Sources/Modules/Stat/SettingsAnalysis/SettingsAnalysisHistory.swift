import CoreData
import Foundation

// MARK: - History values

extension SettingsAnalysis {
    /// A CGM reading in mg/dL.
    struct GlucosePoint: Equatable {
        let date: Date
        let value: Int
    }

    /// A carb entry as the user logged it (fat/protein equivalents excluded).
    struct CarbEvent: Equatable {
        let date: Date
        let grams: Double
    }

    struct BolusEvent: Equatable {
        let date: Date
        let units: Double
        let isSMB: Bool
    }

    struct IOBPoint: Equatable {
        let date: Date
        let iob: Double
    }

    /// Glucose in mg/dL; all arrays sorted by date.
    struct History {
        var glucose: [GlucosePoint] = []
        var carbs: [CarbEvent] = []
        var boluses: [BolusEvent] = []
        /// Periods with a raised temp target or a reduced-insulin override.
        var activity: [DateInterval] = []
        var iob: [IOBPoint] = []
        /// Rewind, prime or site change events.
        var siteChanges: [Date] = []
    }
}

// MARK: - Core Data loader

extension SettingsAnalysis {
    enum HistoryLoader {
        /// Data loaded before the time frame so events near its start have context.
        static let lookback: TimeInterval = 6 * 3600
        /// Site changes are looked up further back to know a site's age.
        static let siteLookback: TimeInterval = 10 * 86400
        /// A temp target at or above this (mg/dL) counts as an activity target.
        static let activityTarget: Decimal = 110

        static func load(
            _ timeFrame: TimeFrame,
            context: NSManagedObjectContext = CoreDataStack.shared.newTaskContext()
        ) async -> History {
            let start = timeFrame.start.addingTimeInterval(-lookback)
            let end = timeFrame.end

            return await context.perform {
                var history = History()
                history.glucose = glucose(from: start, to: end, in: context)
                history.carbs = carbs(from: start, to: end, in: context)
                history.boluses = boluses(from: start, to: end, in: context)
                history.siteChanges = siteChanges(from: start.addingTimeInterval(-siteLookback), to: end, in: context)
                history.activity = activity(from: start, to: end, in: context)
                if !history.activity.isEmpty {
                    history.iob = iob(from: start, to: end, in: context)
                }
                return history
            }
        }

        private static func between(_ key: String, _ start: Date, _ end: Date) -> NSPredicate {
            NSPredicate(format: "%K >= %@ AND %K <= %@", key, start as NSDate, key, end as NSDate)
        }

        private static func dictionaries(
            entity: String,
            properties: [String],
            predicate: NSPredicate,
            sortKey: String,
            in context: NSManagedObjectContext
        ) -> [NSDictionary] {
            let request = NSFetchRequest<NSDictionary>(entityName: entity)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = properties
            request.predicate = predicate
            request.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: true)]
            do {
                return try context.fetch(request)
            } catch {
                warning(.storage, "Settings Analysis: fetching \(entity) failed", error: error)
                return []
            }
        }

        private static func glucose(from start: Date, to end: Date, in context: NSManagedObjectContext) -> [GlucosePoint] {
            dictionaries(
                entity: "GlucoseStored",
                properties: ["date", "glucose"],
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [.cgmGlucose, between("date", start, end)]),
                sortKey: "date",
                in: context
            ).compactMap { row in
                guard let date = row["date"] as? Date,
                      let value = (row["glucose"] as? NSNumber)?.intValue, value > 0
                else { return nil }
                return GlucosePoint(date: date, value: value)
            }
        }

        private static func carbs(from start: Date, to end: Date, in context: NSManagedObjectContext) -> [CarbEvent] {
            dictionaries(
                entity: "CarbEntryStored",
                properties: ["date", "carbs"],
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                    between("date", start, end),
                    NSPredicate(format: "carbs > 0 AND isFPU == NO")
                ]),
                sortKey: "date",
                in: context
            ).compactMap { row in
                guard let date = row["date"] as? Date, let grams = (row["carbs"] as? NSNumber)?.doubleValue else { return nil }
                return CarbEvent(date: date, grams: grams)
            }
        }

        private static func boluses(from start: Date, to end: Date, in context: NSManagedObjectContext) -> [BolusEvent] {
            let request: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                between("timestamp", start, end),
                NSPredicate(format: "bolus != nil")
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            request.relationshipKeyPathsForPrefetching = ["bolus"]
            let events = (try? context.fetch(request)) ?? []
            return events.compactMap { event in
                guard let date = event.timestamp, let bolus = event.bolus,
                      let units = bolus.amount?.doubleValue, units > 0
                else { return nil }
                return BolusEvent(date: date, units: units, isSMB: bolus.isSMB)
            }
        }

        private static func siteChanges(from start: Date, to end: Date, in context: NSManagedObjectContext) -> [Date] {
            let types = [
                PumpEventStored.EventType.siteChange.rawValue,
                PumpEventStored.EventType.rewind.rawValue,
                PumpEventStored.EventType.prime.rawValue
            ]
            let dates = dictionaries(
                entity: "PumpEventStored",
                properties: ["timestamp"],
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                    between("timestamp", start, end),
                    NSPredicate(format: "type IN %@", types)
                ]),
                sortKey: "timestamp",
                in: context
            ).compactMap { $0["timestamp"] as? Date }

            // A rewind and its primes belong to the same site change.
            var merged: [Date] = []
            for date in dates where merged.last.map({ date.timeIntervalSince($0) > 3600 }) ?? true {
                merged.append(date)
            }
            return merged
        }

        private static func iob(from start: Date, to end: Date, in context: NSManagedObjectContext) -> [IOBPoint] {
            dictionaries(
                entity: "OrefDetermination",
                properties: ["deliverAt", "iob"],
                predicate: between("deliverAt", start, end),
                sortKey: "deliverAt",
                in: context
            ).compactMap { row in
                guard let date = row["deliverAt"] as? Date, let iob = (row["iob"] as? NSNumber)?.doubleValue else { return nil }
                return IOBPoint(date: date, iob: iob)
            }
        }

        /// Run entities only exist for cancelled adjustments; expired ones are
        /// rebuilt from the stored row's start and duration.
        private static func activity(from start: Date, to end: Date, in context: NSManagedObjectContext) -> [DateInterval] {
            var intervals: [DateInterval] = []
            let overlaps = NSPredicate(format: "startDate <= %@ AND endDate >= %@", end as NSDate, start as NSDate)

            let tempTargetRuns: NSFetchRequest<TempTargetRunStored> = TempTargetRunStored.fetchRequest()
            tempTargetRuns.predicate = overlaps
            for run in (try? context.fetch(tempTargetRuns)) ?? [] {
                guard let runStart = run.startDate, let runEnd = run.endDate,
                      (run.target as Decimal?) ?? 0 >= activityTarget
                else { continue }
                intervals.append(interval(runStart, runEnd))
            }

            // A run links to its override only until that preset runs again (the relationship is
            // to-one), so older runs of a preset find their percentage through the preset's name.
            let overridePresets: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            overridePresets.predicate = NSPredicate(format: "isPreset == YES")
            var presetPercentage: [String: Double] = [:]
            for preset in (try? context.fetch(overridePresets)) ?? [] {
                if let name = preset.name { presetPercentage[name] = preset.percentage }
            }

            let overrideRuns: NSFetchRequest<OverrideRunStored> = OverrideRunStored.fetchRequest()
            overrideRuns.predicate = overlaps
            overrideRuns.relationshipKeyPathsForPrefetching = ["override"]
            for run in (try? context.fetch(overrideRuns)) ?? [] {
                let percentage = run.override?.percentage ?? run.name.flatMap { presetPercentage[$0] }
                guard let runStart = run.startDate, let runEnd = run.endDate,
                      isActivity(target: run.target as Decimal?, percentage: percentage)
                else { continue }
                intervals.append(interval(runStart, runEnd))
            }

            // Rows without a run: the enabled one (however long ago it started) and older one-off
            // rows. Their end is date + duration (minutes). A row that has a run already ended
            // there, often earlier than its duration.
            let rowWindow = NSPredicate(
                format: "date >= %@ AND date <= %@",
                start.addingTimeInterval(-86400) as NSDate,
                end as NSDate
            )
            func rows(runKey: String) -> NSPredicate {
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "enabled == YES AND date <= %@", end as NSDate),
                    NSCompoundPredicate(andPredicateWithSubpredicates: [
                        rowWindow,
                        NSPredicate(format: "isPreset == NO AND %K == nil", runKey)
                    ])
                ])
            }

            let tempTargets: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            tempTargets.predicate = rows(runKey: "tempTargetRun")
            for row in (try? context.fetch(tempTargets)) ?? [] {
                guard let rowStart = row.date, (row.target as Decimal?) ?? 0 >= activityTarget,
                      let minutes = (row.duration as Decimal?).map({ NSDecimalNumber(decimal: $0).doubleValue }), minutes > 0
                else { continue }
                intervals.append(interval(rowStart, min(rowStart.addingTimeInterval(minutes * 60), end)))
            }

            let overrides: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            overrides.predicate = rows(runKey: "overrideRun")
            for row in (try? context.fetch(overrides)) ?? [] {
                guard let rowStart = row.date,
                      isActivity(target: row.target as Decimal?, percentage: row.percentage) else { continue }
                let minutes = (row.duration as Decimal?).map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
                let rowEnd = row.indefinite || minutes <= 0
                    ? (row.enabled ? end : rowStart)
                    : min(rowStart.addingTimeInterval(minutes * 60), end)
                guard rowEnd > rowStart else { continue }
                intervals.append(interval(rowStart, rowEnd))
            }

            return merge(intervals).filter { $0.end >= start && $0.start <= end }
        }

        private static func isActivity(target: Decimal?, percentage: Double?) -> Bool {
            (target ?? 0) >= activityTarget || (percentage ?? 100) < 100
        }

        private static func interval(_ start: Date, _ end: Date) -> DateInterval {
            DateInterval(start: start, end: max(start, end))
        }

        static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
            var merged: [DateInterval] = []
            for interval in intervals.sorted(by: { $0.start < $1.start }) {
                if let last = merged.last, interval.start <= last.end {
                    merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
                } else {
                    merged.append(interval)
                }
            }
            return merged
        }
    }
}
