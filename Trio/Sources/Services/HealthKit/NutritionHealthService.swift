import Combine
import Foundation
import HealthKit

/// Observes HealthKit nutrition types and records cumulative daily snapshots.
///
/// When the observer fires (new samples written by Cronometer or another app),
/// this service queries the cumulative sum for each macro type for today, builds
/// a `NutritionSnapshot`, and records it to the `NutritionSnapshotStore`.
/// Callbacks are debounced (2 seconds) so all macro types settle before querying.
final class NutritionHealthService {
    private let healthStore: HKHealthStore
    let snapshotStore: NutritionSnapshotStore

    private var observerQueries: [HKObserverQuery] = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 2.0

    /// Fires after a new snapshot is recorded.
    let snapshotRecorded = PassthroughSubject<Void, Never>()

    private let nutritionTypes: [HKQuantityTypeIdentifier] = [
        .dietaryCarbohydrates,
        .dietaryFatTotal,
        .dietaryProtein
    ]

    init(healthStore: HKHealthStore, snapshotStore: NutritionSnapshotStore = NutritionSnapshotStore()) {
        self.healthStore = healthStore
        self.snapshotStore = snapshotStore
    }

    // MARK: - Observer Lifecycle

    func startObserving() {
        // Do an initial snapshot, then register observers
        Task {
            await fetchAndRecordSnapshot()

            for typeID in nutritionTypes {
                guard let sampleType = HKQuantityType.quantityType(forIdentifier: typeID) else { continue }

                let query = HKObserverQuery(sampleType: sampleType, predicate: todayPredicate()) {
                    [weak self] _, completionHandler, error in
                    guard error == nil else {
                        completionHandler()
                        return
                    }
                    self?.scheduleSnapshot()
                    completionHandler()
                }

                healthStore.execute(query)
                observerQueries.append(query)
            }

            debug(.service, "NutritionHealthService: started observing \(nutritionTypes.count) nutrition types")
        }
    }

    func stopObserving() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
        debounceWorkItem?.cancel()
        debug(.service, "NutritionHealthService: stopped observing")
    }

    // MARK: - Debounce

    private func scheduleSnapshot() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { [weak self] in
                await self?.fetchAndRecordSnapshot()
            }
        }
        debounceWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounceDelay, execute: work)
    }

    // MARK: - Snapshot Capture

    /// Query cumulative daily totals for each macro and record a snapshot.
    func fetchAndRecordSnapshot() async {
        async let carbsTotal = queryCumulativeSum(for: .dietaryCarbohydrates)
        async let fatTotal = queryCumulativeSum(for: .dietaryFatTotal)
        async let proteinTotal = queryCumulativeSum(for: .dietaryProtein)

        let (carbs, fat, protein) = await (carbsTotal, fatTotal, proteinTotal)

        // Only record if there's actually some nutrition data
        guard carbs > 0 || fat > 0 || protein > 0 else { return }

        let snapshot = NutritionSnapshot(
            timestamp: Date(),
            cumulativeCarbs: carbs,
            cumulativeFat: fat,
            cumulativeProtein: protein,
            forDate: NutritionSnapshotStore.todayString()
        )

        snapshotStore.record(snapshot)
        snapshotRecorded.send()

        debug(
            .service,
            "NutritionHealthService: snapshot recorded — C:\(String(format: "%.1f", carbs)) F:\(String(format: "%.1f", fat)) P:\(String(format: "%.1f", protein))"
        )
    }

    // MARK: - Sample-Based Meal Detection

    /// Query individual HealthKit samples for today and group them into meals.
    ///
    /// This approach uses actual sample timestamps instead of cumulative-snapshot-deltas,
    /// so meals are correctly separated even after an app restart.
    func fetchGroupedMeals(
        mergeWindow: TimeInterval = 15 * 60,
        dosedTimestamps: Set<TimeInterval> = []
    ) async -> [InferredMealEvent] {
        async let carbSamples = queryIndividualSamples(for: .dietaryCarbohydrates)
        async let fatSamples = queryIndividualSamples(for: .dietaryFatTotal)
        async let proteinSamples = queryIndividualSamples(for: .dietaryProtein)

        let (carbs, fats, proteins) = await (carbSamples, fatSamples, proteinSamples)

        // Merge samples with close timestamps (within 60s) into unified entries.
        // A single Cronometer log creates separate carb/fat/protein samples with
        // nearly identical timestamps — this collapses them into one entry.
        var entries: [MacroEntry] = []
        let entryWindow: TimeInterval = 60

        for (date, value) in carbs {
            if let idx = entries.firstIndex(where: { abs($0.date.timeIntervalSince(date)) < entryWindow }) {
                entries[idx].carbs += value
            } else {
                entries.append(MacroEntry(date: date, carbs: value))
            }
        }

        for (date, value) in fats {
            if let idx = entries.firstIndex(where: { abs($0.date.timeIntervalSince(date)) < entryWindow }) {
                entries[idx].fat += value
            } else {
                entries.append(MacroEntry(date: date, fat: value))
            }
        }

        for (date, value) in proteins {
            if let idx = entries.firstIndex(where: { abs($0.date.timeIntervalSince(date)) < entryWindow }) {
                entries[idx].protein += value
            } else {
                entries.append(MacroEntry(date: date, protein: value))
            }
        }

        entries.sort { $0.date < $1.date }

        // Convert to events, filtering entries with at least 1g of any macro
        let events = entries
            .filter { $0.carbs > 1 || $0.fat > 1 || $0.protein > 1 }
            .map { InferredMealEvent(detectedAt: $0.date, carbsDelta: $0.carbs, fatDelta: $0.fat, proteinDelta: $0.protein) }

        return groupIntoMeals(events: events, mergeWindow: mergeWindow, dosedTimestamps: dosedTimestamps)
    }

    // MARK: - HealthKit Queries

    /// Query the cumulative sum for a nutrition type for today, excluding Trio's own writes.
    private func queryCumulativeSum(for identifier: HKQuantityTypeIdentifier) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: todayPredicate(),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: 0)
                    return
                }

                let externalSamples = samples.filter { sample in
                    sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier
                }

                let total = externalSamples.reduce(0.0) { sum, sample in
                    sum + sample.quantity.doubleValue(for: .gram())
                }

                continuation.resume(returning: total)
            }
            healthStore.execute(query)
        }
    }

    /// Query individual samples for a nutrition type for today, excluding Trio's own writes.
    private func queryIndividualSamples(for identifier: HKQuantityTypeIdentifier) async -> [(Date, Double)] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: todayPredicate(),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let externalSamples = samples.filter { sample in
                    sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier
                }

                let results = externalSamples.map { sample in
                    (sample.startDate, sample.quantity.doubleValue(for: .gram()))
                }

                continuation.resume(returning: results)
            }
            healthStore.execute(query)
        }
    }

    private func todayPredicate() -> NSPredicate {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: .strictStartDate)
    }

    // MARK: - Grouping

    private func groupIntoMeals(
        events: [InferredMealEvent],
        mergeWindow: TimeInterval,
        dosedTimestamps: Set<TimeInterval>
    ) -> [InferredMealEvent] {
        guard !events.isEmpty else { return [] }

        var groups: [InferredMealEvent] = []

        for event in events {
            if let lastIdx = groups.indices.last {
                let lastDate = groups[lastIdx].detectedAt
                let withinWindow = event.detectedAt.timeIntervalSince(lastDate) < mergeWindow

                let doseBetween = dosedTimestamps.contains { ts in
                    ts > lastDate.timeIntervalSince1970 &&
                        ts < event.detectedAt.timeIntervalSince1970
                }

                if withinWindow, !doseBetween {
                    let merged = InferredMealEvent(
                        detectedAt: groups[lastIdx].detectedAt,
                        carbsDelta: groups[lastIdx].carbsDelta + event.carbsDelta,
                        fatDelta: groups[lastIdx].fatDelta + event.fatDelta,
                        proteinDelta: groups[lastIdx].proteinDelta + event.proteinDelta
                    )
                    groups[lastIdx] = merged
                    continue
                }
            }
            groups.append(event)
        }

        return groups
    }

    private struct MacroEntry {
        let date: Date
        var carbs: Double = 0
        var fat: Double = 0
        var protein: Double = 0
    }
}
