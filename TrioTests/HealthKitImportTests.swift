import Foundation
import HealthKit
import Testing

@testable import Trio

/// Tests for HealthKitMealImporter.buildCarbEntries — the pure grouping logic that
/// correlates separate HealthKit carb/fat/protein samples into unified CarbsEntry objects.
///
/// All samples below are created with the default initialiser, which assigns the test
/// runner's bundle as source. In production the equivalent is any NON-Trio source
/// (already filtered upstream before buildCarbEntries is called).
@Suite("HealthKitMealImporter Tests", .serialized)
struct HealthKitMealImporterTests {
    // MARK: - Helpers

    private let carbType = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!
    private let fatType = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!
    private let proteinType = HKObjectType.quantityType(forIdentifier: .dietaryProtein)!

    private func carbSample(grams: Double, at date: Date) -> HKQuantitySample {
        HKQuantitySample(
            type: carbType,
            quantity: HKQuantity(unit: .gram(), doubleValue: grams),
            start: date, end: date
        )
    }

    private func fatSample(grams: Double, at date: Date) -> HKQuantitySample {
        HKQuantitySample(
            type: fatType,
            quantity: HKQuantity(unit: .gram(), doubleValue: grams),
            start: date, end: date
        )
    }

    private func proteinSample(grams: Double, at date: Date) -> HKQuantitySample {
        HKQuantitySample(
            type: proteinType,
            quantity: HKQuantity(unit: .gram(), doubleValue: grams),
            start: date, end: date
        )
    }

    // Fixed reference date so tests are deterministic
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Single-macro entries

    @Test("Carbs-only sample produces one CarbsEntry with fat=nil and protein=nil")
    func testCarbsOnlySample() {
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [carbSample(grams: 40, at: t0)],
            fatSamples: [],
            proteinSamples: []
        )

        #expect(entries.count == 1)
        #expect(entries[0].carbs == 40)
        #expect(entries[0].fat == nil)
        #expect(entries[0].protein == nil)
        #expect(entries[0].enteredBy == CarbsEntry.appleHealth)
    }

    @Test("Fat-only sample produces one CarbsEntry with carbs=0 and protein=nil")
    func testFatOnlySample() {
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [],
            fatSamples: [fatSample(grams: 20, at: t0)],
            proteinSamples: []
        )

        #expect(entries.count == 1)
        #expect(entries[0].carbs == 0)
        #expect(entries[0].fat == 20)
        #expect(entries[0].protein == nil)
    }

    @Test("Protein-only sample produces one CarbsEntry with carbs=0 and fat=nil")
    func testProteinOnlySample() {
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [],
            fatSamples: [],
            proteinSamples: [proteinSample(grams: 30, at: t0)]
        )

        #expect(entries.count == 1)
        #expect(entries[0].carbs == 0)
        #expect(entries[0].fat == nil)
        #expect(entries[0].protein == 30)
    }

    // MARK: - Exact-timestamp grouping

    @Test("Carbs + fat + protein at the same timestamp merge into one CarbsEntry")
    func testExactTimestampGrouping() {
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [carbSample(grams: 50, at: t0)],
            fatSamples: [fatSample(grams: 20, at: t0)],
            proteinSamples: [proteinSample(grams: 30, at: t0)]
        )

        #expect(entries.count == 1)
        #expect(entries[0].carbs == 50)
        #expect(entries[0].fat == 20)
        #expect(entries[0].protein == 30)
    }

    // MARK: - Within-window grouping

    @Test("Samples within the 60-second window merge into one entry")
    func testSamplesWithinWindowMerge() {
        // carbs at T, fat at T+30s, protein at T+45s — all within 60s of T
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [carbSample(grams: 45, at: t0)],
            fatSamples: [fatSample(grams: 15, at: t0.addingTimeInterval(30))],
            proteinSamples: [proteinSample(grams: 25, at: t0.addingTimeInterval(45))]
        )

        #expect(entries.count == 1)
        #expect(entries[0].carbs == 45)
        #expect(entries[0].fat == 15)
        #expect(entries[0].protein == 25)
    }

    @Test("Samples exactly at the window boundary (60s) are included in the same group")
    func testSamplesAtWindowBoundaryIncluded() {
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [carbSample(grams: 30, at: t0)],
            fatSamples: [fatSample(grams: 10, at: t0.addingTimeInterval(60))]
        )

        #expect(entries.count == 1)
        #expect(entries[0].carbs == 30)
        #expect(entries[0].fat == 10)
    }

    // MARK: - Outside-window separation

    @Test("Samples beyond the 60-second window produce separate CarbsEntries")
    func testSamplesOutsideWindowAreSeparate() {
        // Two meals logged 5 minutes apart
        let t1 = t0.addingTimeInterval(5 * 60)

        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [
                carbSample(grams: 40, at: t0),
                carbSample(grams: 60, at: t1)
            ],
            fatSamples: [],
            proteinSamples: []
        )

        #expect(entries.count == 2)
        let sortedEntries = entries.sorted { ($0.actualDate ?? $0.createdAt) < ($1.actualDate ?? $1.createdAt) }
        #expect(sortedEntries[0].carbs == 40)
        #expect(sortedEntries[1].carbs == 60)
    }

    @Test("Fat just beyond 60s window starts a new entry instead of merging")
    func testFatJustBeyondWindowIsNewEntry() {
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [carbSample(grams: 30, at: t0)],
            fatSamples: [fatSample(grams: 10, at: t0.addingTimeInterval(61))]
        )

        #expect(entries.count == 2)
    }

    // MARK: - Multiple distinct meals

    @Test("Three meals spaced 10 minutes apart produce three separate entries")
    func testThreeDistinctMeals() {
        let t1 = t0.addingTimeInterval(10 * 60)
        let t2 = t0.addingTimeInterval(20 * 60)

        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [
                carbSample(grams: 20, at: t0),
                carbSample(grams: 40, at: t1),
                carbSample(grams: 60, at: t2)
            ],
            fatSamples: [
                fatSample(grams: 5, at: t0),
                fatSample(grams: 10, at: t1),
                fatSample(grams: 15, at: t2)
            ],
            proteinSamples: [
                proteinSample(grams: 8, at: t0),
                proteinSample(grams: 16, at: t1),
                proteinSample(grams: 24, at: t2)
            ]
        )

        #expect(entries.count == 3)

        let sorted = entries.sorted { ($0.actualDate ?? $0.createdAt) < ($1.actualDate ?? $1.createdAt) }
        #expect(sorted[0].carbs == 20)
        #expect(sorted[0].fat == 5)
        #expect(sorted[0].protein == 8)

        #expect(sorted[1].carbs == 40)
        #expect(sorted[1].fat == 10)
        #expect(sorted[1].protein == 16)

        #expect(sorted[2].carbs == 60)
        #expect(sorted[2].fat == 15)
        #expect(sorted[2].protein == 24)
    }

    // MARK: - Metadata and identity

    @Test("Each result entry has a unique non-nil id")
    func testEachEntryHasUniqueID() {
        let t1 = t0.addingTimeInterval(10 * 60)
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [
                carbSample(grams: 30, at: t0),
                carbSample(grams: 30, at: t1)
            ],
            fatSamples: [],
            proteinSamples: []
        )

        let ids = entries.compactMap(\.id)
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2, "IDs must be unique")
    }

    @Test("Result entries are tagged with CarbsEntry.appleHealth as enteredBy")
    func testEnteredByIsAppleHealth() {
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [carbSample(grams: 20, at: t0)],
            fatSamples: [fatSample(grams: 10, at: t0)],
            proteinSamples: [proteinSample(grams: 15, at: t0)]
        )

        #expect(entries.allSatisfy { $0.enteredBy == CarbsEntry.appleHealth })
    }

    @Test("Result entries have isFPU set to false")
    func testResultEntriesAreNotFPU() {
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [carbSample(grams: 20, at: t0)],
            fatSamples: [fatSample(grams: 10, at: t0)],
            proteinSamples: []
        )

        #expect(entries.allSatisfy { $0.isFPU == false })
    }

    @Test("Empty input arrays produce no entries")
    func testEmptyInputProducesNoEntries() {
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [],
            fatSamples: [],
            proteinSamples: []
        )

        #expect(entries.isEmpty)
    }

    // MARK: - Custom window

    @Test("Custom 10-second window keeps close samples together and separates distant ones")
    func testCustomGroupingWindow() {
        // fat is 5s after carbs — within custom 10s window → one entry
        // protein is 15s after carbs — outside custom 10s window → separate entry
        let entries = HealthKitMealImporter.buildCarbEntries(
            carbSamples: [carbSample(grams: 30, at: t0)],
            fatSamples: [fatSample(grams: 10, at: t0.addingTimeInterval(5))],
            proteinSamples: [proteinSample(grams: 20, at: t0.addingTimeInterval(15))],
            groupingWindowSeconds: 10
        )

        #expect(entries.count == 2)

        let sorted = entries.sorted { ($0.actualDate ?? $0.createdAt) < ($1.actualDate ?? $1.createdAt) }
        // First group: carbs + fat
        #expect(sorted[0].carbs == 30)
        #expect(sorted[0].fat == 10)
        #expect(sorted[0].protein == nil)
        // Second group: protein only
        #expect(sorted[1].carbs == 0)
        #expect(sorted[1].protein == 20)
    }
}
