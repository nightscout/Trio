import Combine
import Foundation
import HealthKit

/// Detects meals logged in Cronometer (or other nutrition apps) via HealthKit.
///
/// Cronometer writes cumulative daily totals to Apple Health with midnight timestamps.
/// To detect individual meals, we use observer queries that fire when HealthKit data changes,
/// then compute deltas from the previous snapshot.
///
/// A 15-minute merge window groups rapid-fire HealthKit updates into a single meal.
/// Dose boundaries prevent cross-meal merging — once a meal is dosed, subsequent
/// deltas start a new meal.
protocol CronometerMealDetector {
    /// Start observing HealthKit for nutrition changes.
    func startObserving()

    /// Stop observing.
    func stopObserving()

    /// Currently detected undosed meals.
    var detectedMeals: [DetectedMeal] { get }

    /// Publisher for meal list changes.
    var mealsPublisher: AnyPublisher<[DetectedMeal], Never> { get }

    /// Mark a meal as dosed (won't appear as undosed anymore).
    func markAsDosed(_ mealID: UUID)

    /// Clear all detected meals (e.g. on app restart).
    func clearMeals()
}

final class BaseCronometerMealDetector: CronometerMealDetector {
    private let healthStore: HKHealthStore
    private var observerQueries: [HKObserverQuery] = []

    private var _meals: [DetectedMeal] = []
    private let mealsSubject = CurrentValueSubject<[DetectedMeal], Never>([])
    private let mergeWindowSeconds: TimeInterval = 15 * 60 // 15 minutes

    // Previous cumulative snapshot for delta computation
    private var lastCarbsTotal: Double = 0
    private var lastFatTotal: Double = 0
    private var lastProteinTotal: Double = 0
    private var lastFiberTotal: Double = 0
    private var lastSnapshotTime: Date?

    var detectedMeals: [DetectedMeal] { _meals }
    var mealsPublisher: AnyPublisher<[DetectedMeal], Never> { mealsSubject.eraseToAnyPublisher() }

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    // MARK: - Observation

    func startObserving() {
        let nutritionTypes: [HKQuantityTypeIdentifier] = [
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryProtein,
            .dietaryFiber
        ]

        for typeID in nutritionTypes {
            guard let sampleType = HKQuantityType.quantityType(forIdentifier: typeID) else { continue }

            let query = HKObserverQuery(sampleType: sampleType, predicate: todayPredicate()) {
                [weak self] _, completionHandler, error in
                guard error == nil else {
                    completionHandler()
                    return
                }
                Task { [weak self] in
                    await self?.handleNutritionUpdate()
                    completionHandler()
                }
            }

            healthStore.execute(query)
            observerQueries.append(query)
        }

        // Take initial snapshot
        Task {
            await takeSnapshot()
        }

        debug(.service, "CronometerMealDetector: started observing \(nutritionTypes.count) HealthKit nutrition types")
    }

    func stopObserving() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
        debug(.service, "CronometerMealDetector: stopped observing")
    }

    func markAsDosed(_ mealID: UUID) {
        if let idx = _meals.firstIndex(where: { $0.id == mealID }) {
            _meals[idx].isDosed = true
            mealsSubject.send(_meals)
            debug(.service, "CronometerMealDetector: meal \(mealID) marked as dosed")
        }
    }

    func clearMeals() {
        _meals.removeAll()
        mealsSubject.send(_meals)
    }

    // MARK: - Delta Computation

    private func handleNutritionUpdate() async {
        let now = Date()
        let previous = (lastCarbsTotal, lastFatTotal, lastProteinTotal, lastFiberTotal)
        await takeSnapshot()
        let current = (lastCarbsTotal, lastFatTotal, lastProteinTotal, lastFiberTotal)

        let deltaCarbs = current.0 - previous.0
        let deltaFat = current.1 - previous.1
        let deltaProtein = current.2 - previous.2
        let deltaFiber = current.3 - previous.3

        // Only create a meal if there's meaningful carb/macro content
        guard deltaCarbs > 1 || deltaFat > 1 || deltaProtein > 1 else { return }

        // Check if we should merge with the last undosed meal (within merge window)
        if let lastIdx = _meals.lastIndex(where: { !$0.isDosed }),
           now.timeIntervalSince(_meals[lastIdx].detectedAt) < mergeWindowSeconds
        {
            // Merge: add deltas to existing meal
            var meal = _meals[lastIdx]
            meal = DetectedMeal(
                id: meal.id,
                detectedAt: meal.detectedAt,
                carbs: meal.carbs + deltaCarbs,
                fat: meal.fat + deltaFat,
                protein: meal.protein + deltaProtein,
                fiber: meal.fiber + deltaFiber,
                source: meal.source,
                isDosed: false
            )
            _meals[lastIdx] = meal
            debug(.service, "CronometerMealDetector: merged into existing meal — now \(meal.carbs)g carbs")
        } else {
            // New meal
            let meal = DetectedMeal(
                id: UUID(),
                detectedAt: now,
                carbs: deltaCarbs,
                fat: deltaFat,
                protein: deltaProtein,
                fiber: deltaFiber,
                source: "cronometer",
                isDosed: false
            )
            _meals.append(meal)
            debug(.service, "CronometerMealDetector: new meal detected — \(deltaCarbs)g carbs, \(deltaFat)g fat, \(deltaProtein)g protein")
        }

        mealsSubject.send(_meals)
    }

    private func takeSnapshot() async {
        async let carbs = queryCumulativeTotal(for: .dietaryCarbohydrates, unit: .gram())
        async let fat = queryCumulativeTotal(for: .dietaryFatTotal, unit: .gram())
        async let protein = queryCumulativeTotal(for: .dietaryProtein, unit: .gram())
        async let fiber = queryCumulativeTotal(for: .dietaryFiber, unit: .gram())

        let (c, f, p, fb) = await (carbs, fat, protein, fiber)
        lastCarbsTotal = c
        lastFatTotal = f
        lastProteinTotal = p
        lastFiberTotal = fb
        lastSnapshotTime = Date()
    }

    private func queryCumulativeTotal(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: todayPredicate(),
                options: .cumulativeSum
            ) { _, result, _ in
                let total = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: total)
            }
            healthStore.execute(query)
        }
    }

    private func todayPredicate() -> NSPredicate {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: .strictStartDate)
    }
}
