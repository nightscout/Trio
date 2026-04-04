import Foundation
import HealthKit

/// Converts pre-filtered HealthKit dietary samples into ``CarbsEntry`` objects.
///
/// Samples passed in are assumed to come from **external** sources only (i.e. Trio's own
/// previously uploaded samples have already been excluded at the query level). The importer
/// groups closely-timed carb, fat, and protein samples into a single meal entry using a
/// configurable time window.
///
/// ### Grouping algorithm
/// All samples are sorted by `startDate` and processed in chronological order. A new group
/// is started whenever a sample's `startDate` is more than `groupingWindowSeconds` after the
/// **first** sample in the current open group. This prevents a pathological chain-linking
/// effect where many closely spaced samples would collapse into a single giant meal.
///
/// Example with default 60 s window:
/// ```
/// T+0s  carbs 40g  → group A
/// T+30s fat   15g  → group A (30s from T+0)
/// T+70s protein 20g → group B (70s from T+0 exceeds window)
/// ```
enum HealthKitMealImporter {
    // MARK: - Public API

    /// Groups pre-filtered dietary HealthKit samples into ``CarbsEntry`` objects.
    ///
    /// - Parameters:
    ///   - carbSamples: Dietary carbohydrate samples from HealthKit (external sources only).
    ///   - fatSamples: Dietary fat samples from HealthKit (external sources only).
    ///   - proteinSamples: Dietary protein samples from HealthKit (external sources only).
    ///   - groupingWindowSeconds: Maximum gap in seconds between the first sample in a group
    ///     and any subsequent sample for them to be considered the same meal. Defaults to 60.
    /// - Returns: One ``CarbsEntry`` per identified meal, tagged with `CarbsEntry.appleHealth`.
    static func buildCarbEntries(
        carbSamples: [HKQuantitySample],
        fatSamples: [HKQuantitySample],
        proteinSamples: [HKQuantitySample] = [],
        groupingWindowSeconds: TimeInterval = 60
    ) -> [CarbsEntry] {
        // Represent each incoming sample as a typed value + timestamp
        struct TaggedSample {
            enum Macro { case carbs, fat, protein }
            let date: Date
            let grams: Double
            let macro: Macro
        }

        var all: [TaggedSample] = []
        all += carbSamples.map { TaggedSample(date: $0.startDate, grams: $0.quantity.doubleValue(for: .gram()), macro: .carbs) }
        all += fatSamples.map { TaggedSample(date: $0.startDate, grams: $0.quantity.doubleValue(for: .gram()), macro: .fat) }
        all += proteinSamples.map { TaggedSample(date: $0.startDate, grams: $0.quantity.doubleValue(for: .gram()), macro: .protein) }

        guard !all.isEmpty else { return [] }

        all.sort { $0.date < $1.date }

        // Accumulator for an open group
        struct MealGroup {
            let anchorDate: Date   // first sample's date — used as the group boundary
            var carbs: Double = 0
            var fat: Double = 0
            var protein: Double = 0
        }

        var groups: [MealGroup] = []

        for sample in all {
            if let last = groups.last,
               sample.date.timeIntervalSince(last.anchorDate) <= groupingWindowSeconds
            {
                // Append to the current open group
                switch sample.macro {
                case .carbs: groups[groups.count - 1].carbs += sample.grams
                case .fat: groups[groups.count - 1].fat += sample.grams
                case .protein: groups[groups.count - 1].protein += sample.grams
                }
            } else {
                // Open a new group anchored at this sample's date
                var g = MealGroup(anchorDate: sample.date)
                switch sample.macro {
                case .carbs: g.carbs = sample.grams
                case .fat: g.fat = sample.grams
                case .protein: g.protein = sample.grams
                }
                groups.append(g)
            }
        }

        return groups.map { group in
            CarbsEntry(
                id: UUID().uuidString,
                createdAt: group.anchorDate,
                actualDate: group.anchorDate,
                carbs: Decimal(group.carbs),
                fat: group.fat > 0 ? Decimal(group.fat) : nil,
                protein: group.protein > 0 ? Decimal(group.protein) : nil,
                note: nil,
                enteredBy: CarbsEntry.appleHealth,
                isFPU: false,
                fpuID: nil
            )
        }
    }
}
