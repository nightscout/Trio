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
    /// Also captures the latest HealthKit sample creation date (private API)
    /// for accurate meal timestamps — Cronometer sets startDate to midnight.
    func fetchAndRecordSnapshot() async {
        async let carbsResult = queryCumulativeSumWithCreationDate(for: .dietaryCarbohydrates)
        async let fatResult = queryCumulativeSumWithCreationDate(for: .dietaryFatTotal)
        async let proteinResult = queryCumulativeSumWithCreationDate(for: .dietaryProtein)
        async let fiberResult = queryCumulativeSumWithCreationDate(for: .dietaryFiber)

        let (carbsR, fatR, proteinR, fiberR) = await (carbsResult, fatResult, proteinResult, fiberResult)

        let carbs = carbsR.total
        let fat = fatR.total
        let protein = proteinR.total
        let fiber = fiberR.total

        // Only record if there's actually some nutrition data
        guard carbs > 0 || fat > 0 || protein > 0 else { return }

        // Use the most recent creation date across all macro types
        let latestCreationDate = [carbsR.latestCreationDate, fatR.latestCreationDate,
                                  proteinR.latestCreationDate, fiberR.latestCreationDate]
            .compactMap { $0 }
            .max()

        let snapshot = NutritionSnapshot(
            cumulativeCarbs: carbs,
            cumulativeFat: fat,
            cumulativeProtein: protein,
            cumulativeFiber: fiber,
            forDate: NutritionSnapshotStore.todayString(),
            latestSampleCreationDate: latestCreationDate
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
        async let carbsResult = queryCumulativeSumWithCreationDate(for: .dietaryCarbohydrates)
        async let fatResult = queryCumulativeSumWithCreationDate(for: .dietaryFatTotal)
        async let proteinResult = queryCumulativeSumWithCreationDate(for: .dietaryProtein)
        async let fiberResult = queryCumulativeSumWithCreationDate(for: .dietaryFiber)

        let (carbsR, fatR, proteinR, fiberR) = await (carbsResult, fatResult, proteinResult, fiberResult)

        let latestCreationDate = [carbsR.latestCreationDate, fatR.latestCreationDate,
                                  proteinR.latestCreationDate, fiberR.latestCreationDate]
            .compactMap { $0 }
            .max()

        debug(
            .service,
            "NutritionHealthService: fetchLatestMealDelta — C:\(Int(carbsR.total))g F:\(Int(fatR.total))g P:\(Int(proteinR.total))g Fb:\(Int(fiberR.total))g"
        )

        return snapshotStore.recordAndComputeLatestMeal(
            currentCarbs: carbsR.total,
            currentFat: fatR.total,
            currentProtein: proteinR.total,
            currentFiber: fiberR.total,
            latestSampleCreationDate: latestCreationDate
        )
    }

    // MARK: - HealthKit Queries

    private struct CumulativeResult {
        let total: Double
        let latestCreationDate: Date?
    }

    /// Query the cumulative sum and latest sample creation date for a nutrition type today.
    /// Uses the private `creationDate` property on HKObject (via KVC) to get the actual
    /// time data was added to HealthKit — Cronometer sets startDate to midnight.
    private func queryCumulativeSumWithCreationDate(
        for identifier: HKQuantityTypeIdentifier
    ) async -> CumulativeResult {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return CumulativeResult(total: 0, latestCreationDate: nil)
        }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: todayPredicate(),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [trioBundlePrefix] _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: CumulativeResult(total: 0, latestCreationDate: nil))
                    return
                }

                let externalSamples = samples.filter { sample in
                    !sample.sourceRevision.source.bundleIdentifier.hasPrefix(trioBundlePrefix)
                }

                let total = externalSamples.reduce(0.0) { sum, sample in
                    sum + sample.quantity.doubleValue(for: .gram())
                }

                // Access the private creationDate via KVC — this is the "Date Added to Health"
                // shown in the Health app, which reflects when the user actually logged the food.
                let latestCreation = externalSamples
                    .compactMap { $0.value(forKey: "creationDate") as? Date }
                    .max()

                continuation.resume(returning: CumulativeResult(total: total, latestCreationDate: latestCreation))
            }
            healthStore.execute(query)
        }
    }

    private func todayPredicate() -> NSPredicate {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: .strictStartDate)
    }
}
