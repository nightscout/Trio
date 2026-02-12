import Combine
import Foundation
import HealthKit

/// Detects meals logged in Cronometer (or other nutrition apps) via HealthKit.
///
/// Cronometer writes cumulative daily totals to Apple Health with midnight timestamps.
/// To detect individual meals we persist the last-known cumulative snapshot so that
/// app restarts don't produce a false giant meal.  On each HealthKit observer callback
/// we compute the delta from the persisted snapshot.
///
/// Observer callbacks (one per nutrition type) are debounced into a single update.
/// Deltas within a 15-minute window are merged into one meal.
/// Once a meal is marked as dosed, subsequent deltas start a new meal.
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

    // Persisted cumulative snapshot for delta computation
    private var lastCarbsTotal: Double = 0
    private var lastFatTotal: Double = 0
    private var lastProteinTotal: Double = 0
    private var lastFiberTotal: Double = 0

    // Whether a valid prior snapshot exists (false on first install or new day)
    private var hasPriorSnapshot = false

    // Initialization guard — observers don't process until initial reconciliation completes
    private var isInitialized = false

    // Debounce: batch rapid-fire observer callbacks (one fires per nutrition type)
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 2.0

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let prefix = "CronometerMealDetector."
        static let lastCarbs = prefix + "lastCarbsTotal"
        static let lastFat = prefix + "lastFatTotal"
        static let lastProtein = prefix + "lastProteinTotal"
        static let lastFiber = prefix + "lastFiberTotal"
        static let snapshotDay = prefix + "snapshotDay"
        static let meals = prefix + "detectedMeals"
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
        let today = Calendar.current.startOfDay(for: Date())

        // Restore snapshot only if it's from today
        if let savedDay = defaults.object(forKey: Keys.snapshotDay) as? Date,
           Calendar.current.isDate(savedDay, inSameDayAs: today)
        {
            lastCarbsTotal = defaults.double(forKey: Keys.lastCarbs)
            lastFatTotal = defaults.double(forKey: Keys.lastFat)
            lastProteinTotal = defaults.double(forKey: Keys.lastProtein)
            lastFiberTotal = defaults.double(forKey: Keys.lastFiber)
            hasPriorSnapshot = true
        }
        // else: first install or new day — no prior snapshot, just establish baseline

        // Restore today's meals
        if let data = defaults.data(forKey: Keys.meals),
           let saved = try? JSONDecoder().decode([DetectedMeal].self, from: data)
        {
            _meals = saved.filter { Calendar.current.isDateInToday($0.detectedAt) }
        }
        mealsSubject.send(_meals)
    }

    private func persistSnapshot() {
        let defaults = UserDefaults.standard
        defaults.set(lastCarbsTotal, forKey: Keys.lastCarbs)
        defaults.set(lastFatTotal, forKey: Keys.lastFat)
        defaults.set(lastProteinTotal, forKey: Keys.lastProtein)
        defaults.set(lastFiberTotal, forKey: Keys.lastFiber)
        defaults.set(Calendar.current.startOfDay(for: Date()), forKey: Keys.snapshotDay)
    }

    private func persistMeals() {
        if let data = try? JSONEncoder().encode(_meals) {
            UserDefaults.standard.set(data, forKey: Keys.meals)
        }
    }

    // MARK: - Observation

    func startObserving() {
        let nutritionTypes: [HKQuantityTypeIdentifier] = [
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryProtein,
            .dietaryFiber
        ]

        // Reconcile persisted state with current HealthKit data FIRST,
        // then start observers — prevents the race where an observer fires
        // before the initial snapshot is taken.
        Task {
            await reconcileOnStartup()
            isInitialized = true

            for typeID in nutritionTypes {
                guard let sampleType = HKQuantityType.quantityType(forIdentifier: typeID) else { continue }

                let query = HKObserverQuery(sampleType: sampleType, predicate: todayPredicate()) {
                    [weak self] _, completionHandler, error in
                    guard error == nil else {
                        completionHandler()
                        return
                    }
                    // Debounce — don't process immediately; batch all 4 type callbacks
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
        isInitialized = false
        debug(.service, "CronometerMealDetector: stopped observing")
    }

    func markAsDosed(_ mealID: UUID) {
        if let idx = _meals.firstIndex(where: { $0.id == mealID }) {
            _meals[idx].isDosed = true
            mealsSubject.send(_meals)
            persistMeals()
            debug(.service, "CronometerMealDetector: meal \(mealID) marked as dosed")
        }
    }

    func clearMeals() {
        _meals.removeAll()
        mealsSubject.send(_meals)
        persistMeals()
    }

    // MARK: - Startup Reconciliation

    /// Compare persisted snapshot to current HealthKit totals.
    /// On first install or new day (no prior snapshot), just establish the baseline
    /// without creating a meal — the full day's cumulative total isn't a real meal.
    /// On subsequent launches with a valid prior snapshot, detect the delta as a meal.
    private func reconcileOnStartup() async {
        let currentCarbs = await queryCumulativeTotal(for: .dietaryCarbohydrates, unit: .gram())
        let currentFat = await queryCumulativeTotal(for: .dietaryFatTotal, unit: .gram())
        let currentProtein = await queryCumulativeTotal(for: .dietaryProtein, unit: .gram())
        let currentFiber = await queryCumulativeTotal(for: .dietaryFiber, unit: .gram())

        if hasPriorSnapshot {
            // We have a valid baseline — detect the delta since last snapshot
            let deltaCarbs = currentCarbs - lastCarbsTotal
            let deltaFat = currentFat - lastFatTotal
            let deltaProtein = currentProtein - lastProteinTotal
            let deltaFiber = currentFiber - lastFiberTotal

            if deltaCarbs > 1 || deltaFat > 1 || deltaProtein > 1 {
                appendOrMergeMeal(
                    deltaCarbs: max(0, deltaCarbs),
                    deltaFat: max(0, deltaFat),
                    deltaProtein: max(0, deltaProtein),
                    deltaFiber: max(0, deltaFiber),
                    at: Date()
                )
                persistMeals()
            }
        } else {
            // First install or new day — just establish the baseline, don't create a meal
            debug(
                .service,
                "CronometerMealDetector: no prior snapshot — establishing baseline (C:\(currentCarbs) F:\(currentFat) P:\(currentProtein) Fb:\(currentFiber))"
            )
        }

        // Update snapshot to current cumulative totals
        lastCarbsTotal = currentCarbs
        lastFatTotal = currentFat
        lastProteinTotal = currentProtein
        lastFiberTotal = currentFiber
        hasPriorSnapshot = true
        persistSnapshot()

        debug(
            .service,
            "CronometerMealDetector: reconciled — C:\(currentCarbs) F:\(currentFat) P:\(currentProtein) Fb:\(currentFiber)"
        )
    }

    // MARK: - Debounced Update

    /// Debounce rapid-fire observer callbacks (one per nutrition type) into a single update.
    private func scheduleUpdate() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { [weak self] in
                await self?.handleNutritionUpdate()
            }
        }
        debounceWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounceDelay, execute: work)
    }

    // MARK: - Delta Computation

    private func handleNutritionUpdate() async {
        guard isInitialized else { return }

        let previous = (lastCarbsTotal, lastFatTotal, lastProteinTotal, lastFiberTotal)
        await takeSnapshot()
        let current = (lastCarbsTotal, lastFatTotal, lastProteinTotal, lastFiberTotal)

        let deltaCarbs = current.0 - previous.0
        let deltaFat = current.1 - previous.1
        let deltaProtein = current.2 - previous.2
        let deltaFiber = current.3 - previous.3

        // Always persist the updated snapshot (cumulative totals may change even without a new meal)
        persistSnapshot()

        // Ignore negative deltas (user removed food) and trivial changes
        guard deltaCarbs > 1 || deltaFat > 1 || deltaProtein > 1 else { return }

        appendOrMergeMeal(
            deltaCarbs: max(0, deltaCarbs),
            deltaFat: max(0, deltaFat),
            deltaProtein: max(0, deltaProtein),
            deltaFiber: max(0, deltaFiber),
            at: Date()
        )
        persistMeals()
    }

    // MARK: - Meal Creation / Merging

    /// Append a new meal or merge into the most recent undosed meal if within the 15-minute window.
    private func appendOrMergeMeal(
        deltaCarbs: Double,
        deltaFat: Double,
        deltaProtein: Double,
        deltaFiber: Double,
        at timestamp: Date
    ) {
        if let lastIdx = _meals.lastIndex(where: { !$0.isDosed }),
           timestamp.timeIntervalSince(_meals[lastIdx].detectedAt) < mergeWindowSeconds
        {
            // Merge into existing undosed meal
            let meal = _meals[lastIdx]
            _meals[lastIdx] = DetectedMeal(
                id: meal.id,
                detectedAt: meal.detectedAt,
                carbs: meal.carbs + deltaCarbs,
                fat: meal.fat + deltaFat,
                protein: meal.protein + deltaProtein,
                fiber: meal.fiber + deltaFiber,
                source: meal.source,
                isDosed: false
            )
            debug(
                .service,
                "CronometerMealDetector: merged delta into meal — now \(_meals[lastIdx].carbs)g C"
            )
        } else {
            // New meal
            let meal = DetectedMeal(
                id: UUID(),
                detectedAt: timestamp,
                carbs: deltaCarbs,
                fat: deltaFat,
                protein: deltaProtein,
                fiber: deltaFiber,
                source: "cronometer",
                isDosed: false
            )
            _meals.append(meal)
            debug(
                .service,
                "CronometerMealDetector: new meal — \(deltaCarbs)g C, \(deltaFat)g F, \(deltaProtein)g P"
            )
        }

        mealsSubject.send(_meals)
    }

    // MARK: - HealthKit Queries

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
