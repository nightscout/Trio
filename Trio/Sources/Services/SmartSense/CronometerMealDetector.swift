import Combine
import Foundation
import HealthKit

/// Detects meals logged in Cronometer (or other nutrition apps) via HealthKit.
///
/// Uses a sample-based approach: when HealthKit nutrition data changes, individual
/// samples are queried and grouped by their actual timestamps (not the poll time).
/// This ensures `detectedAt` reflects when the meal was actually logged, not when
/// Trio happened to read it. Samples within a 15-minute window are grouped as a
/// single meal. Dose timestamps create group boundaries — dosing between two
/// samples forces them into separate meals even if they're within the merge window.
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

    // Map dosed meal timestamps so we can preserve isDosed across rebuilds
    // and create group boundaries for meal inference
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
        // Primary: sample-based meal events with actual HealthKit timestamps
        nutritionService.rawMealEventsDetected
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] rawEvents in
                self?.rebuildMealsFromSampleEvents(rawEvents)
            }
            .store(in: &cancellables)

        // Fallback: snapshot-delta detection (fires first, uses poll timestamps)
        nutritionService.snapshotRecorded
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] in
                self?.rebuildMealsFromSnapshots()
            }
            .store(in: &cancellables)

        // Start the HealthKit observers (triggers initial snapshot + meal detection)
        nutritionService.startObserving()

        debug(.service, "CronometerMealDetector: started observing via sample-based detection")
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

    // MARK: - Snapshot-Delta Fallback

    /// Infer meals from snapshot deltas (fires first; uses poll timestamps).
    /// Will be superseded by sample-based events when they arrive.
    private func rebuildMealsFromSnapshots() {
        let events = nutritionService.snapshotStore.inferredMeals(
            mergeWindow: 15 * 60,
            dosedTimestamps: dosedMealTimestamps
        )
        applyMealEvents(events)
    }

    // MARK: - Sample-Based Meal Detection

    /// Rebuild detected meals from raw sample-based events (with actual HealthKit timestamps).
    /// Fires after rebuildMealsFromSnapshots and overwrites with accurate timestamps.
    private func rebuildMealsFromSampleEvents(_ rawEvents: [InferredMealEvent]) {
        // Group raw events using dose timestamps as boundaries
        let events = nutritionService.groupIntoMeals(
            events: rawEvents,
            mergeWindow: 15 * 60,
            dosedTimestamps: dosedMealTimestamps
        )
        applyMealEvents(events)
    }

    /// Common path: convert InferredMealEvents into DetectedMeals and publish.
    private func applyMealEvents(_ events: [InferredMealEvent]) {
        var newMeals: [DetectedMeal] = []
        for event in events {
            let wasDosed = dosedMealTimestamps.contains(event.detectedAt.timeIntervalSince1970)

            // Try to find existing meal with matching timestamp to preserve its ID
            let existingMeal = _meals.first { meal in
                abs(meal.detectedAt.timeIntervalSince(event.detectedAt)) < 1.0
            }

            let meal = DetectedMeal(
                id: existingMeal?.id ?? UUID(),
                detectedAt: event.detectedAt,
                carbs: event.carbsDelta,
                fat: event.fatDelta,
                protein: event.proteinDelta,
                fiber: event.fiberDelta,
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

            let mealSummary = newMeals.map { "[\(Int($0.carbs))C/\(Int($0.fat))F/\(Int($0.protein))P/\(Int($0.fiber))Fb]" }.joined(separator: " ")
            debug(.service, "CronometerMealDetector: \(newMeals.count) meals — \(mealSummary)")
        }
    }
}
