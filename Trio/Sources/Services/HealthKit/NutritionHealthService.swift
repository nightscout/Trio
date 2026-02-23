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

    /// Bundle identifier prefix for Trio to filter out its own entries.
    private let trioBundlePrefix = "org.nightscout"

    /// Fires after a new snapshot is recorded.
    let snapshotRecorded = PassthroughSubject<Void, Never>()

    /// All four macro types we track from Apple Health.
    private let nutritionTypes: [HKQuantityTypeIdentifier] = [
        .dietaryCarbohydrates,
        .dietaryFatTotal,
        .dietaryProtein,
        .dietaryFiber
    ]

    init(healthStore: HKHealthStore, snapshotStore: NutritionSnapshotStore = .shared) {
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

                let query = HKObserverQuery(sampleType: sampleType, predicate: nil) {
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

            // Enable background delivery for carbs so we detect meals even when backgrounded
            if let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
                healthStore.enableBackgroundDelivery(for: carbType, frequency: .immediate) { success, error in
                    if success {
                        debug(.service, "NutritionHealthService: background delivery enabled for carbs")
                    } else if let error {
                        debug(.service, "NutritionHealthService: background delivery failed — \(error.localizedDescription)")
                    }
                }
            }

            debug(.service, "NutritionHealthService: started observing \(nutritionTypes.count) nutrition types with background delivery")
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
        async let fiberTotal = queryCumulativeSum(for: .dietaryFiber)

        let (carbs, fat, protein, fiber) = await (carbsTotal, fatTotal, proteinTotal, fiberTotal)

        // Only record if there's actually some nutrition data
        guard carbs > 0 || fat > 0 || protein > 0 else { return }

        let snapshot = NutritionSnapshot(
            cumulativeCarbs: carbs,
            cumulativeFat: fat,
            cumulativeProtein: protein,
            cumulativeFiber: fiber,
            forDate: NutritionSnapshotStore.todayString()
        )

        snapshotStore.record(snapshot)
        snapshotRecorded.send()

        debug(
            .service,
            "NutritionHealthService: snapshot — C:\(String(format: "%.1f", carbs)) F:\(String(format: "%.1f", fat)) P:\(String(format: "%.1f", protein)) Fb:\(String(format: "%.1f", fiber))"
        )
    }

    // MARK: - On-Demand Meal Fetch (Crono Button)

    /// Query current cumulative nutrition totals from Apple Health and return
    /// the delta since the last snapshot (i.e. the most recently logged food).
    func fetchLatestMealDelta() async -> InferredMealEvent? {
        async let carbsTotal = queryCumulativeSum(for: .dietaryCarbohydrates)
        async let fatTotal = queryCumulativeSum(for: .dietaryFatTotal)
        async let proteinTotal = queryCumulativeSum(for: .dietaryProtein)
        async let fiberTotal = queryCumulativeSum(for: .dietaryFiber)

        let (carbs, fat, protein, fiber) = await (carbsTotal, fatTotal, proteinTotal, fiberTotal)

        debug(
            .service,
            "NutritionHealthService: fetchLatestMealDelta — C:\(Int(carbs))g F:\(Int(fat))g P:\(Int(protein))g Fb:\(Int(fiber))g"
        )

        return snapshotStore.recordAndComputeLatestMeal(
            currentCarbs: carbs,
            currentFat: fat,
            currentProtein: protein,
            currentFiber: fiber
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
        async let fiberSamples = queryIndividualSamples(for: .dietaryFiber)

        let (carbs, fats, proteins, fibers) = await (carbSamples, fatSamples, proteinSamples, fiberSamples)

        // Merge samples with close timestamps (within 60s) into unified entries.
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

        for (date, value) in fibers {
            if let idx = entries.firstIndex(where: { abs($0.date.timeIntervalSince(date)) < entryWindow }) {
                entries[idx].fiber += value
            } else {
                entries.append(MacroEntry(date: date, fiber: value))
            }
        }

        entries.sort { $0.date < $1.date }

        let events = entries
            .filter { $0.carbs > 1 || $0.fat > 1 || $0.protein > 1 }
            .map {
                InferredMealEvent(
                    detectedAt: $0.date,
                    carbsDelta: $0.carbs,
                    fatDelta: $0.fat,
                    proteinDelta: $0.protein,
                    fiberDelta: $0.fiber
                )
            }

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
            ) { [trioBundlePrefix] _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: 0)
                    return
                }

                let externalSamples = samples.filter { sample in
                    !sample.sourceRevision.source.bundleIdentifier.hasPrefix(trioBundlePrefix)
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
            ) { [trioBundlePrefix] _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let externalSamples = samples.filter { sample in
                    !sample.sourceRevision.source.bundleIdentifier.hasPrefix(trioBundlePrefix)
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
                        id: groups[lastIdx].id,
                        detectedAt: groups[lastIdx].detectedAt,
                        carbsDelta: groups[lastIdx].carbsDelta + event.carbsDelta,
                        fatDelta: groups[lastIdx].fatDelta + event.fatDelta,
                        proteinDelta: groups[lastIdx].proteinDelta + event.proteinDelta,
                        fiberDelta: groups[lastIdx].fiberDelta + event.fiberDelta
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
        var fiber: Double = 0
    }
}
