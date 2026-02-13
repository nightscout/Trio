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

    // MARK: - HealthKit Queries

    /// Query the cumulative sum for a nutrition type for today, excluding Trio's own writes.
    private func queryCumulativeSum(for identifier: HKQuantityTypeIdentifier) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }

        return await withCheckedContinuation { continuation in
            // Use a sample query to filter by source, then sum manually
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

                // Filter out Trio's own writes
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

    private func todayPredicate() -> NSPredicate {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: .strictStartDate)
    }
}
