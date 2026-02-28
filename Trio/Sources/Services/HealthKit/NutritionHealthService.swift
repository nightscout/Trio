import Combine
import Foundation
import HealthKit

/// Observes HealthKit nutrition types and detects meals directly from samples.
///
/// When the observer fires (new samples written by Cronometer or another app),
/// this service queries all individual nutrition samples for today, groups them
/// by their `creationDate` (the private "Date Added to Health" field) within
/// a 15-minute window, and publishes the grouped meals.
///
/// This is simpler than the old snapshot-delta approach: no cumulative totals,
/// no snapshots, no deltas. Just read the samples, group them, done.
final class NutritionHealthService {
    private let healthStore: HKHealthStore

    private var observerQueries: [HKObserverQuery] = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 2.0

    /// Bundle identifier prefix for Trio to filter out its own entries.
    private let trioBundlePrefix = "org.nightscout"

    /// Fires after meals are refreshed from HealthKit samples.
    let mealsDetected = PassthroughSubject<[DetectedMeal], Never>()

    /// All four macro types we track from Apple Health.
    private let nutritionTypes: [HKQuantityTypeIdentifier] = [
        .dietaryCarbohydrates,
        .dietaryFatTotal,
        .dietaryProtein,
        .dietaryFiber
    ]

    /// Window for grouping samples into a single meal (15 minutes).
    private let mealGroupingWindow: TimeInterval = 15 * 60

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    // MARK: - Observer Lifecycle

    func startObserving() {
        Task {
            await fetchAndPublishMeals()

            for typeID in nutritionTypes {
                guard let sampleType = HKQuantityType.quantityType(forIdentifier: typeID) else { continue }

                let query = HKObserverQuery(sampleType: sampleType, predicate: nil) {
                    [weak self] _, completionHandler, error in
                    guard error == nil else {
                        completionHandler()
                        return
                    }
                    self?.scheduleFetch()
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

    private func scheduleFetch() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { [weak self] in
                await self?.fetchAndPublishMeals()
            }
        }
        debounceWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounceDelay, execute: work)
    }

    // MARK: - Meal Detection

    /// Query all nutrition samples for today, group by creationDate, publish as meals.
    func fetchAndPublishMeals() async {
        let meals = await queryAndGroupMeals()
        mealsDetected.send(meals)

        if !meals.isEmpty {
            let summary = meals.map { "[\(Int($0.carbs))C/\(Int($0.fat))F/\(Int($0.protein))P]" }.joined(separator: " ")
            debug(.service, "NutritionHealthService: \(meals.count) meals — \(summary)")
        }
    }

    /// Query all individual samples for today and group into meals by creationDate.
    private func queryAndGroupMeals() async -> [DetectedMeal] {
        // Query all four macro types in parallel
        async let carbSamples = queryExternalSamples(for: .dietaryCarbohydrates)
        async let fatSamples = queryExternalSamples(for: .dietaryFatTotal)
        async let proteinSamples = queryExternalSamples(for: .dietaryProtein)
        async let fiberSamples = queryExternalSamples(for: .dietaryFiber)

        let (carbs, fats, proteins, fibers) = await (carbSamples, fatSamples, proteinSamples, fiberSamples)

        // Collect all samples with their creationDate and macro type into a flat list
        struct TaggedSample {
            let creationDate: Date
            let grams: Double
            enum MacroType { case carbs, fat, protein, fiber }
            let type: MacroType
        }

        var allSamples: [TaggedSample] = []

        for sample in carbs {
            let date = (sample.value(forKey: "creationDate") as? Date) ?? sample.endDate
            allSamples.append(TaggedSample(creationDate: date, grams: sample.quantity.doubleValue(for: .gram()), type: .carbs))
        }
        for sample in fats {
            let date = (sample.value(forKey: "creationDate") as? Date) ?? sample.endDate
            allSamples.append(TaggedSample(creationDate: date, grams: sample.quantity.doubleValue(for: .gram()), type: .fat))
        }
        for sample in proteins {
            let date = (sample.value(forKey: "creationDate") as? Date) ?? sample.endDate
            allSamples.append(TaggedSample(creationDate: date, grams: sample.quantity.doubleValue(for: .gram()), type: .protein))
        }
        for sample in fibers {
            let date = (sample.value(forKey: "creationDate") as? Date) ?? sample.endDate
            allSamples.append(TaggedSample(creationDate: date, grams: sample.quantity.doubleValue(for: .gram()), type: .fiber))
        }

        guard !allSamples.isEmpty else { return [] }

        // Sort all samples by creationDate
        allSamples.sort { $0.creationDate < $1.creationDate }

        // Group into meals: samples within 15 minutes of the group's first sample
        struct MealAccumulator {
            var startDate: Date
            var latestDate: Date
            var carbs: Double = 0
            var fat: Double = 0
            var protein: Double = 0
            var fiber: Double = 0
        }

        var groups: [MealAccumulator] = []

        for sample in allSamples {
            // Try to add to the last group if within the window
            if var last = groups.last,
               sample.creationDate.timeIntervalSince(last.startDate) <= mealGroupingWindow
            {
                switch sample.type {
                case .carbs: last.carbs += sample.grams
                case .fat: last.fat += sample.grams
                case .protein: last.protein += sample.grams
                case .fiber: last.fiber += sample.grams
                }
                last.latestDate = max(last.latestDate, sample.creationDate)
                groups[groups.count - 1] = last
            } else {
                // Start a new group
                var acc = MealAccumulator(startDate: sample.creationDate, latestDate: sample.creationDate)
                switch sample.type {
                case .carbs: acc.carbs = sample.grams
                case .fat: acc.fat = sample.grams
                case .protein: acc.protein = sample.grams
                case .fiber: acc.fiber = sample.grams
                }
                groups.append(acc)
            }
        }

        // Convert groups to DetectedMeal, filtering out trivial entries
        return groups.compactMap { group in
            guard group.carbs > 1 || group.fat > 1 || group.protein > 1 else { return nil }
            return DetectedMeal(
                id: UUID(),
                detectedAt: group.startDate,
                carbs: group.carbs,
                fat: group.fat,
                protein: group.protein,
                fiber: group.fiber,
                source: "cronometer",
                isDosed: false
            )
        }
    }

    // MARK: - HealthKit Queries

    /// Query individual samples for a nutrition type today, excluding Trio's own writes.
    private func queryExternalSamples(for identifier: HKQuantityTypeIdentifier) async -> [HKQuantitySample] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: todayPredicate(),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [trioBundlePrefix] _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let external = samples.filter { sample in
                    !sample.sourceRevision.source.bundleIdentifier.hasPrefix(trioBundlePrefix)
                }

                continuation.resume(returning: external)
            }
            healthStore.execute(query)
        }
    }

    private func todayPredicate() -> NSPredicate {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: .strictStartDate)
    }
}
