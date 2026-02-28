import Combine
import Foundation
import HealthKit

/// Observes HealthKit nutrition types and detects meals via cumulative-total deltas.
///
/// Cronometer (and similar apps) re-sync all daily samples at once, so they all
/// share the same `creationDate`. We can't distinguish meals by sample timestamps.
/// Instead, we track cumulative daily totals over time: each time the observer fires,
/// we query the sum, compare to last known totals, and treat the increase as a meal.
/// Deltas within 15 minutes are merged into a single meal.
///
/// **Lifecycle:** `startObserving()` is idempotent and starts HK observers once.
/// The observers run for the lifetime of the process — they are never stopped.
/// This ensures deltas are captured even when the UI navigates away from Treatments.
///
/// State (lastKnownTotals + detected meals) is persisted to UserDefaults so we
/// survive app restarts.
final class NutritionHealthService {
    private let healthStore: HKHealthStore

    private var observerQueries: [HKObserverQuery] = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 2.0

    /// Prevents double-starting HK observers.
    private var isObserving = false

    /// Bundle identifier prefix for Trio to filter out its own entries.
    private let trioBundlePrefix = "org.nightscout"

    /// Current meal list. Uses CurrentValueSubject so late subscribers (e.g. when
    /// the Treatments view re-appears) immediately receive the latest meals.
    let mealsDetected = CurrentValueSubject<[DetectedMeal], Never>([])

    /// All four macro types we track from Apple Health.
    private let nutritionTypes: [HKQuantityTypeIdentifier] = [
        .dietaryCarbohydrates,
        .dietaryFatTotal,
        .dietaryProtein,
        .dietaryFiber
    ]

    /// Window for merging consecutive deltas into a single meal (15 minutes).
    private let mealGroupingWindow: TimeInterval = 15 * 60

    // MARK: - Persisted State

    private struct Macros: Codable {
        var carbs: Double = 0
        var fat: Double = 0
        var protein: Double = 0
        var fiber: Double = 0
    }

    private struct MealDelta: Codable {
        let detectedAt: Date
        var carbs: Double
        var fat: Double
        var protein: Double
        var fiber: Double
    }

    /// Last known cumulative totals from HealthKit.
    private var lastKnownTotals = Macros()

    /// The date (yyyy-MM-dd) that lastKnownTotals applies to.
    private var lastKnownDate: String = ""

    /// Accumulated meal deltas for today.
    private var accumulatedMeals: [MealDelta] = []

    /// When the last delta was detected (for 15-min merge window).
    private var lastDeltaTime: Date?

    private enum Keys {
        static let prefix = "NutritionHealthService."
        static let totals = prefix + "lastKnownTotals"
        static let date = prefix + "lastKnownDate"
        static let meals = prefix + "accumulatedMeals"
        static let lastDelta = prefix + "lastDeltaTime"
    }

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        restoreState()
    }

    // MARK: - Persistence

    private func restoreState() {
        let defaults = UserDefaults.standard
        let today = Self.todayString()

        if let data = defaults.data(forKey: Keys.totals),
           let totals = try? JSONDecoder().decode(Macros.self, from: data)
        {
            lastKnownTotals = totals
        }

        lastKnownDate = defaults.string(forKey: Keys.date) ?? ""

        if let data = defaults.data(forKey: Keys.meals),
           let meals = try? JSONDecoder().decode([MealDelta].self, from: data)
        {
            accumulatedMeals = meals
        }

        if let interval = defaults.object(forKey: Keys.lastDelta) as? Double {
            lastDeltaTime = Date(timeIntervalSince1970: interval)
        }

        // Day rollover: reset if stored state is from a different day
        if lastKnownDate != today {
            lastKnownTotals = Macros()
            lastKnownDate = today
            accumulatedMeals = []
            lastDeltaTime = nil
            persistState()
        }

        // Publish restored meals immediately so CurrentValueSubject has them
        publishCurrentMeals()
    }

    private func persistState() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(lastKnownTotals) {
            defaults.set(data, forKey: Keys.totals)
        }
        defaults.set(lastKnownDate, forKey: Keys.date)
        if let data = try? JSONEncoder().encode(accumulatedMeals) {
            defaults.set(data, forKey: Keys.meals)
        }
        if let t = lastDeltaTime {
            defaults.set(t.timeIntervalSince1970, forKey: Keys.lastDelta)
        }
    }

    private static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    // MARK: - Observer Lifecycle

    /// Start HealthKit observers. Idempotent — safe to call multiple times.
    /// Once started, observers run for the lifetime of the process.
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

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

    // MARK: - Delta-Based Meal Detection

    /// Query cumulative totals, compute delta from last known, update meal list.
    func fetchAndPublishMeals() async {
        // Handle day rollover
        let today = Self.todayString()
        if lastKnownDate != today {
            lastKnownTotals = Macros()
            lastKnownDate = today
            accumulatedMeals = []
            lastDeltaTime = nil
        }

        let currentTotals = await queryCumulativeTotals()

        let deltaCarbs = currentTotals.carbs - lastKnownTotals.carbs
        let deltaFat = currentTotals.fat - lastKnownTotals.fat
        let deltaProtein = currentTotals.protein - lastKnownTotals.protein
        let deltaFiber = currentTotals.fiber - lastKnownTotals.fiber

        // Only record if there's a meaningful increase in at least one macro
        if deltaCarbs > 1 || deltaFat > 1 || deltaProtein > 1 {
            let now = Date()

            // Merge with last meal if within 15-minute window
            if let lt = lastDeltaTime,
               now.timeIntervalSince(lt) <= mealGroupingWindow,
               !accumulatedMeals.isEmpty
            {
                let idx = accumulatedMeals.count - 1
                accumulatedMeals[idx].carbs += max(0, deltaCarbs)
                accumulatedMeals[idx].fat += max(0, deltaFat)
                accumulatedMeals[idx].protein += max(0, deltaProtein)
                accumulatedMeals[idx].fiber += max(0, deltaFiber)
            } else {
                accumulatedMeals.append(MealDelta(
                    detectedAt: now,
                    carbs: max(0, deltaCarbs),
                    fat: max(0, deltaFat),
                    protein: max(0, deltaProtein),
                    fiber: max(0, deltaFiber)
                ))
            }

            lastDeltaTime = now
            lastKnownTotals = currentTotals
            persistState()

            debug(
                .service,
                "NutritionHealthService: delta +\(Int(deltaCarbs))C/+\(Int(deltaFat))F/+\(Int(deltaProtein))P → \(accumulatedMeals.count) meals"
            )
        } else if currentTotals.carbs != lastKnownTotals.carbs ||
            currentTotals.fat != lastKnownTotals.fat ||
            currentTotals.protein != lastKnownTotals.protein
        {
            // Totals changed but not a meaningful increase (possible delete or sub-1g change)
            lastKnownTotals = currentTotals
            persistState()
        }

        // Always publish current meal list
        publishCurrentMeals()
    }

    /// Publish the current accumulated meals via the CurrentValueSubject.
    private func publishCurrentMeals() {
        let meals = accumulatedMeals.map { delta in
            DetectedMeal(
                id: UUID(),
                detectedAt: delta.detectedAt,
                carbs: delta.carbs,
                fat: delta.fat,
                protein: delta.protein,
                fiber: delta.fiber,
                source: "cronometer",
                isDosed: false
            )
        }
        mealsDetected.send(meals)
    }

    // MARK: - HealthKit Queries

    /// Query cumulative (summed) totals for all four macros today.
    private func queryCumulativeTotals() async -> Macros {
        async let c = querySumForType(.dietaryCarbohydrates)
        async let f = querySumForType(.dietaryFatTotal)
        async let p = querySumForType(.dietaryProtein)
        async let fb = querySumForType(.dietaryFiber)

        let (carbs, fat, protein, fiber) = await (c, f, p, fb)
        return Macros(carbs: carbs, fat: fat, protein: protein, fiber: fiber)
    }

    /// Query the sum of all external samples for a nutrition type today.
    private func querySumForType(_ identifier: HKQuantityTypeIdentifier) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return 0
        }

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

                let total = samples
                    .filter { !$0.sourceRevision.source.bundleIdentifier.hasPrefix(trioBundlePrefix) }
                    .reduce(0.0) { $0 + $1.quantity.doubleValue(for: .gram()) }

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
