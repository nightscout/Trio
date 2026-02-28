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

    private func todayPredicate() -> NSPredicate {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: .strictStartDate)
    }
}
