import Combine
import Foundation
import HealthKit

/// Detects meals logged in Cronometer (or other nutrition apps) via HealthKit.
///
/// Rather than tracking cumulative totals (which suffer from race conditions when
/// HealthKit fires observers before all macro samples are committed), this detector
/// queries individual nutrition samples and groups them by timestamp.  Any samples
/// with timestamps within a 15-minute window are treated as a single meal.
///
/// Observer callbacks (one per nutrition type) are debounced into a single update.
/// Once a meal is marked as dosed, subsequent entries start a new meal.
protocol CronometerMealDetector {
    /// Start observing HealthKit for nutrition changes.
    func startObserving()

    /// Stop observing.
    func stopObserving()

    /// Currently detected meals (includes dosed ones).
    var detectedMeals: [DetectedMeal] { get }

    /// Publisher for meal list changes.
    var mealsPublisher: AnyPublisher<[DetectedMeal], Never> { get }

    /// Mark a meal as dosed (won't appear as undosed anymore).
    func markAsDosed(_ mealID: UUID)

    /// Clear all detected meals.
    func clearMeals()
}

final class BaseCronometerMealDetector: CronometerMealDetector {
    private let healthStore: HKHealthStore
    private var observerQueries: [HKObserverQuery] = []

    private var _meals: [DetectedMeal] = []
    private let mealsSubject = CurrentValueSubject<[DetectedMeal], Never>([])
    private let mergeWindowSeconds: TimeInterval = 15 * 60 // 15 minutes

    // Debounce: batch rapid-fire observer callbacks (one fires per nutrition type)
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 3.0

    // Track the last-processed sample date so we don't re-process old samples
    private var lastProcessedDate: Date?

    // Map dosed meal timestamps so we can preserve isDosed across rebuilds
    private var dosedMealTimestamps: Set<TimeInterval> = []

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let prefix = "CronometerMealDetector."
        static let meals = prefix + "detectedMeals"
        static let lastProcessed = prefix + "lastProcessedDate"
        static let dosedTimestamps = prefix + "dosedTimestamps"
    }

    var detectedMeals: [DetectedMeal] { _meals }
    var mealsPublisher: AnyPublisher<[DetectedMeal], Never> { mealsSubject.eraseToAnyPublisher() }

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        restorePersistedState()
    }

    // MARK: - Persistence

    private func restorePersistedState() {
        let defaults = UserDefaults.standard

        // Restore today's meals
        if let data = defaults.data(forKey: Keys.meals),
           let saved = try? JSONDecoder().decode([DetectedMeal].self, from: data)
        {
            _meals = saved.filter { Calendar.current.isDateInToday($0.detectedAt) }
            dosedMealTimestamps = Set(
                _meals.filter(\.isDosed).map { $0.detectedAt.timeIntervalSince1970 }
            )
        }

        // Restore last processed date
        if let ts = defaults.object(forKey: Keys.lastProcessed) as? Double, ts > 0 {
            lastProcessedDate = Date(timeIntervalSince1970: ts)
            // If it's from a previous day, reset
            if let date = lastProcessedDate, !Calendar.current.isDateInToday(date) {
                lastProcessedDate = nil
            }
        }

        // Restore dosed timestamps
        if let arr = defaults.array(forKey: Keys.dosedTimestamps) as? [Double] {
            dosedMealTimestamps = Set(arr)
        }

        mealsSubject.send(_meals)
    }

    private func persistMeals() {
        if let data = try? JSONEncoder().encode(_meals) {
            UserDefaults.standard.set(data, forKey: Keys.meals)
        }
    }

    private func persistLastProcessed() {
        if let date = lastProcessedDate {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.lastProcessed)
        }
    }

    private func persistDosedTimestamps() {
        UserDefaults.standard.set(Array(dosedMealTimestamps), forKey: Keys.dosedTimestamps)
    }

    // MARK: - Observation

    func startObserving() {
        let nutritionTypes: [HKQuantityTypeIdentifier] = [
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryProtein,
            .dietaryFiber
        ]

        // Do an initial scan, then start observers
        Task {
            await rebuildMealsFromSamples()

            for typeID in nutritionTypes {
                guard let sampleType = HKQuantityType.quantityType(forIdentifier: typeID) else { continue }

                let query = HKObserverQuery(sampleType: sampleType, predicate: todayPredicate()) {
                    [weak self] _, completionHandler, error in
                    guard error == nil else {
                        completionHandler()
                        return
                    }
                    self?.scheduleUpdate()
                    completionHandler()
                }

                healthStore.execute(query)
                observerQueries.append(query)
            }

            debug(.service, "CronometerMealDetector: started observing \(nutritionTypes.count) HealthKit nutrition types")
        }
    }

    func stopObserving() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
        debounceWorkItem?.cancel()
        debug(.service, "CronometerMealDetector: stopped observing")
    }

    func markAsDosed(_ mealID: UUID) {
        if let idx = _meals.firstIndex(where: { $0.id == mealID }) {
            _meals[idx].isDosed = true
            dosedMealTimestamps.insert(_meals[idx].detectedAt.timeIntervalSince1970)
            mealsSubject.send(_meals)
            persistMeals()
            persistDosedTimestamps()
            debug(.service, "CronometerMealDetector: meal \(mealID) marked as dosed")
        }
    }

    func clearMeals() {
        _meals.removeAll()
        dosedMealTimestamps.removeAll()
        mealsSubject.send(_meals)
        persistMeals()
        persistDosedTimestamps()
    }

    // MARK: - Debounced Update

    private func scheduleUpdate() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { [weak self] in
                await self?.rebuildMealsFromSamples()
            }
        }
        debounceWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounceDelay, execute: work)
    }

    // MARK: - Sample-Based Meal Detection

    /// Query all nutrition samples for today and group them into meals.
    /// Samples within 15 minutes of each other are considered the same meal.
    private func rebuildMealsFromSamples() async {
        // Query all 4 nutrition types for today
        async let carbSamples = querySamples(for: .dietaryCarbohydrates, unit: .gram())
        async let fatSamples = querySamples(for: .dietaryFatTotal, unit: .gram())
        async let proteinSamples = querySamples(for: .dietaryProtein, unit: .gram())
        async let fiberSamples = querySamples(for: .dietaryFiber, unit: .gram())

        let (carbs, fats, proteins, fibers) = await (carbSamples, fatSamples, proteinSamples, fiberSamples)

        // Combine all samples into a unified timeline
        var allEntries: [(date: Date, carbs: Double, fat: Double, protein: Double, fiber: Double)] = []

        for s in carbs { allEntries.append((s.date, s.value, 0, 0, 0)) }
        for s in fats { allEntries.append((s.date, 0, s.value, 0, 0)) }
        for s in proteins { allEntries.append((s.date, 0, 0, s.value, 0)) }
        for s in fibers { allEntries.append((s.date, 0, 0, 0, s.value)) }

        // Sort by date
        allEntries.sort { $0.date < $1.date }

        // Group into meals: entries within 15 minutes of each other
        var mealGroups: [(date: Date, carbs: Double, fat: Double, protein: Double, fiber: Double)] = []

        for entry in allEntries {
            if let lastIdx = mealGroups.indices.last,
               entry.date.timeIntervalSince(mealGroups[lastIdx].date) < mergeWindowSeconds
            {
                // Merge into current meal group
                mealGroups[lastIdx].carbs += entry.carbs
                mealGroups[lastIdx].fat += entry.fat
                mealGroups[lastIdx].protein += entry.protein
                mealGroups[lastIdx].fiber += entry.fiber
            } else {
                // Start a new meal group
                mealGroups.append((entry.date, entry.carbs, entry.fat, entry.protein, entry.fiber))
            }
        }

        // Filter out trivial groups (< 1g carbs AND < 1g fat AND < 1g protein)
        mealGroups = mealGroups.filter { $0.carbs > 1 || $0.fat > 1 || $0.protein > 1 }

        // Build DetectedMeal list, preserving isDosed state
        var newMeals: [DetectedMeal] = []
        for group in mealGroups {
            let wasDosed = dosedMealTimestamps.contains(group.date.timeIntervalSince1970)

            // Try to find existing meal with matching timestamp to preserve its ID
            let existingMeal = _meals.first { meal in
                abs(meal.detectedAt.timeIntervalSince(group.date)) < 1.0
            }

            let meal = DetectedMeal(
                id: existingMeal?.id ?? UUID(),
                detectedAt: group.date,
                carbs: group.carbs,
                fat: group.fat,
                protein: group.protein,
                fiber: group.fiber,
                source: "cronometer",
                isDosed: wasDosed || (existingMeal?.isDosed ?? false)
            )
            newMeals.append(meal)
        }

        let changed = newMeals.count != _meals.count ||
            zip(newMeals, _meals).contains(where: { $0 != $1 })

        if changed {
            _meals = newMeals
            mealsSubject.send(_meals)
            persistMeals()

            let mealSummary = newMeals.map { "[\(Int($0.carbs))C/\(Int($0.fat))F/\(Int($0.protein))P]" }.joined(separator: " ")
            debug(.service, "CronometerMealDetector: \(newMeals.count) meals — \(mealSummary)")
        }
    }

    // MARK: - HealthKit Sample Queries

    private struct NutritionSample {
        let date: Date
        let value: Double
    }

    private func querySamples(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> [NutritionSample] {
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

                // Filter out samples that Trio itself wrote (avoid double-counting)
                let externalSamples = samples.filter { sample in
                    sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier
                }

                let result = externalSamples.map { sample in
                    NutritionSample(
                        date: sample.startDate,
                        value: sample.quantity.doubleValue(for: unit)
                    )
                }
                continuation.resume(returning: result)
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
