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

    /// A temp target or override. Named ones are identified by name, unnamed custom ones by
    /// their values, so the user can pick which ones they use for exercise.
    struct Adjustment: Hashable, Identifiable {
        enum Kind: String {
            case tempTarget
            case override
        }

        let kind: Kind
        /// Preset or custom name; nil for unnamed custom adjustments.
        let name: String?
        /// mg/dL
        let target: Decimal?
        let percentage: Double?

        init(kind: Kind, name: String?, target: Decimal?, percentage: Double? = nil) {
            self.kind = kind
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.name = Self.defaultNames.contains(trimmed) ? nil : trimmed
            self.target = target
            self.percentage = percentage
        }

        /// Names Trio gives custom adjustments, which say nothing about their purpose.
        private static let defaultNames: Set<String> = [
            "",
            "Custom",
            "Custom Override",
            "Custom Temp Target",
            String(localized: "Custom Override"),
            String(localized: "Custom Temp Target")
        ]

        var id: String {
            if let name { return "\(kind.rawValue):\(name)" }
            let target = self.target.map { "\(NSDecimalNumber(decimal: $0).intValue)" } ?? "-"
            let percentage = self.percentage.map { "\(Int($0.rounded()))" } ?? "-"
            return "\(kind.rawValue):custom:\(target):\(percentage)"
        }

        /// A raised temp target or a reduced-insulin override; the exercise selection
        /// until the user picks their own.
        var suggestsExercise: Bool {
            (target ?? 0) >= HistoryLoader.activityTarget || (percentage ?? 100) < 100
        }

        static func == (lhs: Adjustment, rhs: Adjustment) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    struct AdjustmentPeriod: Equatable {
        let adjustment: Adjustment
        let interval: DateInterval
    }

    /// How often an adjustment ran, for the exercise selection.
    /// Presets that never ran have a count of 0.
    struct AdjustmentUsage: Identifiable, Equatable {
        let adjustment: Adjustment
        let count: Int
        let duration: TimeInterval
        var id: String { adjustment.id }
        /// A preset that never ran.
        var isUnused: Bool { count < 1 }

        static func usages(
            of periods: [AdjustmentPeriod],
            presets: [Adjustment] = [],
            in timeFrame: TimeFrame
        ) -> [AdjustmentUsage] {
            let inFrame = periods.filter { $0.interval.end >= timeFrame.start && $0.interval.start <= timeFrame.end }
            var usages = Dictionary(grouping: inFrame, by: \.adjustment.id).compactMapValues { group in
                group.first.map {
                    AdjustmentUsage(
                        adjustment: $0.adjustment,
                        count: group.count,
                        duration: group.map(\.interval.duration).reduce(0, +)
                    )
                }
            }
            for preset in presets where usages[preset.id] == nil {
                usages[preset.id] = AdjustmentUsage(adjustment: preset, count: 0, duration: 0)
            }
            return usages.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
        }
    }

    /// Glucose in mg/dL; all arrays sorted by date.
    struct History {
        var glucose: [GlucosePoint] = []
        var carbs: [CarbEvent] = []
        var boluses: [BolusEvent] = []
        /// Every temp target and override, whatever it was used for.
        var adjustments: [AdjustmentPeriod] = []
        /// Merged periods of the adjustments used for exercise.
        var activity: [DateInterval] = []
        var iob: [IOBPoint] = []
        /// Rewind, prime or site change events.
        var siteChanges: [Date] = []

        /// Rebuilds `activity` from the adjustments used for exercise (by `Adjustment.id`);
        /// `nil` means the user has not picked any, so those that suggest exercise are used.
        mutating func selectExercise(_ exercise: Set<String>?) {
            activity = HistoryLoader.merge(
                adjustments.filter { exercise?.contains($0.adjustment.id) ?? $0.adjustment.suggestsExercise }
                    .map(\.interval)
            )
        }
    }
}

// MARK: - Core Data loader

extension SettingsAnalysis {
    enum HistoryLoader {
        /// Data loaded before the time frame so events near its start have context.
        static let lookback: TimeInterval = 6 * 3600
        /// Site changes are looked up further back to know a site's age.
        static let siteLookback: TimeInterval = 10 * 86400
        /// A temp target at or above this (mg/dL) suggests exercise.
        static let activityTarget: Decimal = 110

        static func load(
            _ timeFrame: TimeFrame,
            exerciseAdjustments: Set<String>? = nil,
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
                history.adjustments = adjustmentPeriods(from: start, to: end, in: context)
                history.selectExercise(exerciseAdjustments)
                if !history.activity.isEmpty {
                    history.iob = iob(from: start, to: end, in: context)
                }
                return history
            }
        }

        /// Every preset plus every temp target and override ever used, for choosing which are
        /// for exercise. Not limited to a time frame, so the list stays the same whatever is analyzed.
        static func adjustmentUsages(
            now: Date = Date(),
            context: NSManagedObjectContext = CoreDataStack.shared.newTaskContext()
        ) async -> [AdjustmentUsage] {
            let timeFrame = TimeFrame(start: .distantPast, end: now)
            return await context.perform {
                AdjustmentUsage.usages(
                    of: adjustmentPeriods(from: timeFrame.start, to: timeFrame.end, in: context),
                    presets: presets(in: context),
                    in: timeFrame
                )
            }
        }

        private static func presets(in context: NSManagedObjectContext) -> [Adjustment] {
            let isPreset = NSPredicate(format: "isPreset == YES")
            let tempTargets: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            tempTargets.predicate = isPreset
            let overrides: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            overrides.predicate = isPreset
            return ((try? context.fetch(tempTargets)) ?? []).map {
                Adjustment(kind: .tempTarget, name: $0.name, target: $0.target as Decimal?)
            } + ((try? context.fetch(overrides)) ?? []).map {
                Adjustment(kind: .override, name: $0.name, target: $0.target as Decimal?, percentage: $0.percentage)
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
        private static func adjustmentPeriods(
            from start: Date,
            to end: Date,
            in context: NSManagedObjectContext
        ) -> [AdjustmentPeriod] {
            var periods: [AdjustmentPeriod] = []
            let overlaps = NSPredicate(format: "startDate <= %@ AND endDate >= %@", end as NSDate, start as NSDate)

            let tempTargetRuns: NSFetchRequest<TempTargetRunStored> = TempTargetRunStored.fetchRequest()
            tempTargetRuns.predicate = overlaps
            tempTargetRuns.relationshipKeyPathsForPrefetching = ["tempTarget"]
            for run in (try? context.fetch(tempTargetRuns)) ?? [] {
                guard let runStart = run.startDate, let runEnd = run.endDate else { continue }
                let target = run.target as Decimal?
                let adjustment = Adjustment(kind: .tempTarget, name: run.name ?? run.tempTarget?.name, target: target)
                periods.append(AdjustmentPeriod(adjustment: adjustment, interval: interval(runStart, runEnd)))
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
                guard let runStart = run.startDate, let runEnd = run.endDate else { continue }
                let adjustment = Adjustment(
                    kind: .override,
                    name: run.name ?? run.override?.name,
                    target: run.target as Decimal?,
                    percentage: percentage
                )
                periods.append(AdjustmentPeriod(adjustment: adjustment, interval: interval(runStart, runEnd)))
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
                guard let rowStart = row.date, let target = row.target as Decimal?,
                      let minutes = (row.duration as Decimal?).map({ NSDecimalNumber(decimal: $0).doubleValue }), minutes > 0
                else { continue }
                periods.append(AdjustmentPeriod(
                    adjustment: Adjustment(kind: .tempTarget, name: row.name, target: target),
                    interval: interval(rowStart, min(rowStart.addingTimeInterval(minutes * 60), end))
                ))
            }

            let overrides: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            overrides.predicate = rows(runKey: "overrideRun")
            for row in (try? context.fetch(overrides)) ?? [] {
                guard let rowStart = row.date else { continue }
                let minutes = (row.duration as Decimal?).map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
                let rowEnd = row.indefinite || minutes <= 0
                    ? (row.enabled ? end : rowStart)
                    : min(rowStart.addingTimeInterval(minutes * 60), end)
                guard rowEnd > rowStart else { continue }
                periods.append(AdjustmentPeriod(
                    adjustment: Adjustment(
                        kind: .override,
                        name: row.name,
                        target: row.target as Decimal?,
                        percentage: row.percentage
                    ),
                    interval: interval(rowStart, rowEnd)
                ))
            }

            return periods
                .filter { $0.interval.end >= start && $0.interval.start <= end }
                .sorted { $0.interval.start < $1.interval.start }
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
