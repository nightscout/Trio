import Combine
import Foundation
import HealthKit

/// Detects meals logged in Cronometer (or other nutrition apps) via HealthKit.
///
/// `NutritionHealthService` queries individual HealthKit samples, groups them
/// by their `creationDate` (the "Date Added to Health" timestamp) within a
/// 15-minute window, and publishes the results as `[DetectedMeal]`.
///
/// This detector subscribes to those updates, preserves `isDosed` state across
/// refreshes, and publishes the final meal list for the UI.
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
    private let nutritionService: NutritionHealthService

    private var _meals: [DetectedMeal] = []
    private let mealsSubject = CurrentValueSubject<[DetectedMeal], Never>([])

    /// Timestamps of dosed meals — used to preserve isDosed across refreshes.
    private(set) var dosedMealTimestamps: Set<TimeInterval> = []

    private var cancellables = Set<AnyCancellable>()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let prefix = "CronometerMealDetector."
        static let meals = prefix + "detectedMeals"
        static let dosedTimestamps = prefix + "dosedTimestamps"
    }

    var detectedMeals: [DetectedMeal] { _meals }
    var mealsPublisher: AnyPublisher<[DetectedMeal], Never> { mealsSubject.eraseToAnyPublisher() }

    init(healthStore: HKHealthStore) {
        nutritionService = NutritionHealthService(healthStore: healthStore)
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

    private func persistDosedTimestamps() {
        UserDefaults.standard.set(Array(dosedMealTimestamps), forKey: Keys.dosedTimestamps)
    }

    // MARK: - Observation

    func startObserving() {
        // Subscribe to meal updates from the nutrition service
        nutritionService.mealsDetected
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] freshMeals in
                self?.applyFreshMeals(freshMeals)
            }
            .store(in: &cancellables)

        // Start the HealthKit observers (triggers initial fetch too)
        nutritionService.startObserving()

        debug(.service, "CronometerMealDetector: started observing")
    }

    func stopObserving() {
        nutritionService.stopObserving()
        cancellables.removeAll()
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

    // MARK: - Apply Fresh Meals from HealthKit

    /// Merge fresh meals from HealthKit with local dosed state.
    private func applyFreshMeals(_ freshMeals: [DetectedMeal]) {
        var newMeals: [DetectedMeal] = []

        for meal in freshMeals {
            let wasDosed = dosedMealTimestamps.contains(meal.detectedAt.timeIntervalSince1970)

            // Preserve existing meal ID if timestamps match (within 1 second)
            let existingMeal = _meals.first { existing in
                abs(existing.detectedAt.timeIntervalSince(meal.detectedAt)) < 1.0
            }

            newMeals.append(DetectedMeal(
                id: existingMeal?.id ?? meal.id,
                detectedAt: meal.detectedAt,
                carbs: meal.carbs,
                fat: meal.fat,
                protein: meal.protein,
                fiber: meal.fiber,
                source: meal.source,
                isDosed: wasDosed || (existingMeal?.isDosed ?? false)
            ))
        }

        let changed = newMeals.count != _meals.count ||
            zip(newMeals, _meals).contains(where: { $0 != $1 })

        if changed {
            _meals = newMeals
            mealsSubject.send(_meals)
            persistMeals()

            let summary = newMeals.map { "[\(Int($0.carbs))C/\(Int($0.fat))F/\(Int($0.protein))P]" }.joined(separator: " ")
            debug(.service, "CronometerMealDetector: \(newMeals.count) meals — \(summary)")
        }
    }
}
