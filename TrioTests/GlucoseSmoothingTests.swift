import CoreData
import Foundation
import LoopKitUI
import Swinject
import Testing

@testable import Trio

@Suite("Glucose Smoothing Tests", .serialized) struct GlucoseSmoothingTests: Injectable {
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!
    var fetchGlucoseManager: BaseFetchGlucoseManager!
    var openAPS: OpenAPS!

    init() async throws {
        coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()

        let assembler = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: testContext)
        ])

        resolver = assembler.resolver
        injectServices(resolver)

        fetchGlucoseManager = resolver.resolve(FetchGlucoseManager.self)! as? BaseFetchGlucoseManager

        let fileStorage = resolver.resolve(FileStorage.self)!
        openAPS = OpenAPS(storage: fileStorage, tddStorage: MockTDDStorage())
    }

    // MARK: - Adaptive Smoothing Tests

    @Test(
        "Adaptive smoothing writes smoothed glucose for CGM values when enough data exists"
    ) func testAdaptiveSmoothingStoresSmoothedValues() async throws {
        let glucoseValues: [Int16] = [100, 105, 110, 115, 120, 125]
        await createGlucoseSequence(values: glucoseValues, interval: 5 * 60, isManual: false)

        await fetchGlucoseManager.applyGlucoseSmoothing(context: testContext)

        let fetchedAscending = try await fetchAndSortGlucose()

        // We expect at least the most recent few values to get smoothed values written.
        // The Kotlin/port writes to data[i] for i in 0..<limit, where data is newest-first.
        // With 6 values:
        // - recordCount = 6
        // - validWindowCount starts at 5, no gap => remains 5
        // - smoothing produces blended.count == 5
        // - apply limit = min(5, 6) = 5 => most recent 5 entries get smoothedGlucose
        //
        // In ascending order, "most recent 5" are indices 1...5. Oldest (index 0) is not guaranteed to be updated.
        #expect(fetchedAscending.count == 6)

        let smoothedValues = fetchedAscending.compactMap { $0.smoothedGlucose?.decimalValue }
        #expect(smoothedValues.count >= 5, "Expected at least 5 smoothed values to be stored.")

        for (i, value) in smoothedValues.enumerated() {
            #expect(value >= 39, "Smoothed glucose at index \(i) should be clamped to at least 39, got \(value).")
            #expect(
                value == value.rounded(toPlaces: 0),
                "Smoothed glucose at index \(i) should be rounded to an integer, got \(value)."
            )
        }
    }

    @Test("Adaptive smoothing does not smooth manual glucose entries") func testAdaptiveSmoothingIgnoresManual() async throws {
        // GIVEN: Mixed manual + CGM values
        await createGlucoseSequence(values: [100, 105, 110, 115, 120].map(Int16.init), interval: 5 * 60, isManual: false)
        await createGlucose(glucose: 130, smoothed: nil, isManual: true, date: Date().addingTimeInterval(6 * 5 * 60))

        // WHEN
        await fetchGlucoseManager.applyGlucoseSmoothing(context: testContext)

        // THEN
        let allAscending = try await fetchAndSortGlucose()
        let manual = allAscending.first(where: { $0.isManual })

        #expect(manual != nil, "Expected a manual glucose entry.")
        #expect(manual?.smoothedGlucose == nil, "Manual entries must not be smoothed/stored.")
    }

    @Test(
        "Adaptive smoothing clamps smoothed glucose to >= 39 and rounds to integer"
    ) func testAdaptiveSmoothingClampAndRounding() async throws {
        // GIVEN
        let glucoseValues: [Int16] = [40, 39, 41, 42, 43, 44]
        await createGlucoseSequence(values: glucoseValues, interval: 5 * 60, isManual: false)

        // WHEN
        await fetchGlucoseManager.applyGlucoseSmoothing(context: testContext)

        // THEN
        let fetchedAscending = try await fetchAndSortGlucose()

        let smoothedValues = fetchedAscending
            .compactMap { $0.smoothedGlucose?.decimalValue }
            .filter { $0 > 0 }

        #expect(!smoothedValues.isEmpty, "Expected at least one smoothed glucose value to be stored.")

        for (index, smoothed) in smoothedValues.enumerated() {
            #expect(
                smoothed >= 39,
                "Smoothed glucose must be clamped to >= 39, got \(smoothed) at index \(index)."
            )

            #expect(
                smoothed == smoothed.rounded(toPlaces: 0),
                "Smoothed glucose must be an integer value, got \(smoothed) at index \(index)."
            )
        }
    }

    // MARK: - fetchGlucose Window Tests

    @Test(
        "fetchGlucose retains the most recent 350 readings (not the oldest) when 24h holds more than 350"
    ) func testFetchGlucoseKeepsMostRecentWhenOverLimit() async throws {
        // GIVEN: 360 readings within the last 24h (3 min spacing => ~18h span).
        // Each reading carries a unique glucose value so we can verify which subset survives the limit.
        let count = 360
        let values: [Int16] = (0 ..< count).map { Int16(100 + $0) }
        await createGlucoseSequence(values: values, interval: 3 * 60, isManual: false)

        // WHEN
        let objectIDs = try await fetchGlucoseManager.fetchGlucose(context: testContext)

        // THEN
        #expect(objectIDs.count == 350, "fetchGlucose should respect the 350 limit, got \(objectIDs.count).")

        await testContext.perform {
            let fetched = objectIDs.compactMap { self.testContext.object(with: $0) as? GlucoseStored }
            #expect(fetched.count == 350, "All returned object IDs must resolve to GlucoseStored instances.")

            // Returned order must be oldest-first (chronological) — the smoother walks the array this way.
            let dates = fetched.compactMap(\.date)
            #expect(dates == dates.sorted(), "fetchGlucose must return readings in chronological (ascending) order.")

            // The most recent reading (current BG) must be the LAST element after the chronological reverse.
            #expect(
                fetched.last?.glucose == Int16(100 + count - 1),
                "Most recent reading (current BG) must be retained after the 350-limit truncation."
            )

            // The oldest 10 readings must be dropped — verify the limit cut from the OLD end, not the recent end.
            let returnedGlucoseValues = Set(fetched.map(\.glucose))
            #expect(
                !returnedGlucoseValues.contains(Int16(100)),
                "Oldest reading must be excluded by the limit (truncation should cut old, not recent)."
            )
            #expect(
                returnedGlucoseValues.contains(Int16(100 + count - 1)),
                "Newest reading must be included after truncation."
            )
        }
    }

    @Test(
        "Adaptive smoothing writes a smoothed value for the current BG when 24h holds more than 350 readings"
    ) func testAdaptiveSmoothingCoversCurrentBGAboveLimit() async throws {
        // GIVEN: 360 contiguous CGM readings within the last 24h (3 min spacing, no gaps).
        let count = 360
        let values: [Int16] = (0 ..< count).map { _ in Int16(120) }
        await createGlucoseSequence(values: values, interval: 3 * 60, isManual: false)

        // WHEN
        await fetchGlucoseManager.applyGlucoseSmoothing(context: testContext)

        // THEN: the most recent reading must have received a smoothed value.
        // Regression test for the bug where ascending+fetchLimit kept the OLDEST 350 readings,
        // so the current BG fell outside the smoothing window and was never written.
        let ascending = try await fetchAndSortGlucose()
        // The in-memory test store is shared across this serialized suite, so readings from other
        // tests may also be present. Assert at least our created readings exist; the current-BG check
        // below is the actual regression this test guards.
        #expect(ascending.count >= count)

        #expect(
            ascending.last?.smoothedGlucose != nil,
            "Most recent reading (current BG) must receive a smoothed value when over the 350-row limit."
        )
    }

    // MARK: - OpenAPS Glucose Selection Tests

    @Test("Algorithm uses smoothed glucose when enabled") func testAlgorithmUsesSmoothedGlucose() async throws {
        await createGlucose(glucose: 150, smoothed: 140, isManual: false, date: Date())

        let algorithmInput = try await runFetchAndProcessGlucose(smoothGlucose: true)

        #expect(algorithmInput.count == 1, "Expected to process one glucose entry.")
        #expect(
            algorithmInput.first?.glucose == 140,
            "Algorithm should have used the smoothed glucose value (140), but used \(algorithmInput.first?.glucose ?? 0)."
        )
    }

    @Test("Algorithm uses raw glucose when smoothing is disabled") func testAlgorithmUsesRawGlucose() async throws {
        await createGlucose(glucose: 150, smoothed: 140, isManual: false, date: Date())

        let algorithmInput = try await runFetchAndProcessGlucose(smoothGlucose: false)

        #expect(algorithmInput.count == 1, "Expected to process one glucose entry.")
        #expect(
            algorithmInput.first?.glucose == 150,
            "Algorithm should have used the raw glucose value (150), but used \(algorithmInput.first?.glucose ?? 0)."
        )
    }

    @Test("Algorithm falls back to raw glucose if smoothed value is missing") func testAlgorithmFallbackToRawGlucose() async throws {
        await createGlucose(glucose: 150, smoothed: nil, isManual: false, date: Date())

        let algorithmInput = try await runFetchAndProcessGlucose(smoothGlucose: true)

        #expect(algorithmInput.count == 1, "Expected to process one glucose entry.")
        #expect(
            algorithmInput.first?.glucose == 150,
            "Algorithm should have fallen back to the raw glucose value (150), but used \(algorithmInput.first?.glucose ?? 0)."
        )
    }

    @Test("Algorithm ignores smoothed value for manual glucose entries") func testAlgorithmIgnoresSmoothedManualGlucose() async throws {
        await createGlucose(glucose: 150, smoothed: 140, isManual: true, date: Date())

        let algorithmInput = try await runFetchAndProcessGlucose(smoothGlucose: true)

        #expect(algorithmInput.count == 1, "Expected to process one glucose entry.")
        #expect(
            algorithmInput.first?.glucose == 150,
            "Algorithm should have ignored smoothing for a manual entry and used the raw value (150), but used \(algorithmInput.first?.glucose ?? 0)."
        )
    }

    // MARK: - Helpers

    private func runFetchAndProcessGlucose(smoothGlucose: Bool) async throws -> [AlgorithmGlucose] {
        let jsonString = try await openAPS.fetchAndProcessGlucose(
            context: testContext,
            shouldSmoothGlucose: smoothGlucose,
            fetchLimit: 10
        )

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateDouble = try container.decode(Double.self)
            return Date(timeIntervalSince1970: dateDouble / 1000)
        }

        return try decoder.decode([AlgorithmGlucose].self, from: data)
    }

    private func createGlucose(glucose: Int16, smoothed: Decimal?, isManual: Bool, date: Date) async {
        await testContext.perform {
            let object = GlucoseStored(context: self.testContext)
            object.date = date
            object.glucose = glucose
            object.smoothedGlucose = smoothed as NSDecimalNumber?
            object.isManual = isManual
            object.id = UUID()
            try! self.testContext.save()
        }
    }

    private func createGlucoseSequence(values: [Int16], dates: [Date], isManual: Bool) async {
        precondition(values.count == dates.count)

        await testContext.perform {
            for (i, value) in values.enumerated() {
                let object = GlucoseStored(context: self.testContext)
                object.date = dates[i]
                object.glucose = value
                object.smoothedGlucose = nil
                object.isManual = isManual
                object.id = UUID()
            }
            try! self.testContext.save()
        }
    }

    private func createGlucoseSequence(values: [Int16], interval: TimeInterval, isManual: Bool) async {
        let now = Date()
        let dates = values.indices.map { now.addingTimeInterval(Double($0) * interval) }
        await createGlucoseSequence(values: values, dates: dates, isManual: isManual)
    }

    private func fetchAndSortGlucose() async throws -> [GlucoseStored] {
        try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: testContext,
            predicate: .all,
            key: "date",
            ascending: true
        ) as? [GlucoseStored] ?? []
    }
}
