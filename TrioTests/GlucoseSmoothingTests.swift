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

    // MARK: - Exponential Smoothing Tests

    @Test(
        "Exponential smoothing writes smoothed glucose for CGM values when enough data exists"
    ) func testExponentialSmoothingStoresSmoothedValues() async throws {
        let glucoseValues: [Int16] = [100, 105, 110, 115, 120, 125]
        await createGlucoseSequence(values: glucoseValues, interval: 5 * 60, isManual: false)

        await fetchGlucoseManager.exponentialSmoothingGlucose(context: testContext)

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

    @Test("Exponential smoothing does not smooth manual glucose entries") func testExponentialSmoothingIgnoresManual() async throws {
        // GIVEN: Mixed manual + CGM values
        await createGlucoseSequence(values: [100, 105, 110, 115, 120].map(Int16.init), interval: 5 * 60, isManual: false)
        await createGlucose(glucose: 130, smoothed: nil, isManual: true, date: Date().addingTimeInterval(6 * 5 * 60))

        // WHEN
        await fetchGlucoseManager.exponentialSmoothingGlucose(context: testContext)

        // THEN
        let allAscending = try await fetchAndSortGlucose()
        let manual = allAscending.first(where: { $0.isManual })

        #expect(manual != nil, "Expected a manual glucose entry.")
        #expect(manual?.smoothedGlucose == nil, "Manual entries must not be smoothed/stored.")
    }

    @Test(
        "Exponential smoothing clamps smoothed glucose to >= 39 and rounds to integer"
    ) func testExponentialSmoothingClampAndRounding() async throws {
        // GIVEN
        let glucoseValues: [Int16] = [40, 39, 41, 42, 43, 44]
        await createGlucoseSequence(values: glucoseValues, interval: 5 * 60, isManual: false)

        // WHEN
        await fetchGlucoseManager.exponentialSmoothingGlucose(context: testContext)

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

    @Test(
        "Exponential smoothing stops at gaps >= 12 minutes and only updates the most recent window"
    ) func testExponentialSmoothingGapStopsWindow() async throws {
        let now = Date()

        var dates: [Date] = []
        var values: [Int16] = []

        // Older contiguous block (should remain untouched)
        for i in 0 ..< 10 {
            dates.append(now.addingTimeInterval(Double(i) * 5 * 60))
            values.append(Int16(100 + i * 5))
        }

        // GAP (15 minutes)
        let gapStart = now.addingTimeInterval(Double(10) * 5 * 60 + 15 * 60)

        // Recent block (too small -> fallback applies only here)
        for i in 0 ..< 3 {
            dates.append(gapStart.addingTimeInterval(Double(i) * 5 * 60))
            values.append(Int16(200 + i * 5))
        }

        await createGlucoseSequence(values: values, dates: dates, isManual: false)

        await fetchGlucoseManager.exponentialSmoothingGlucose(context: testContext)

        let ascending = try await fetchAndSortGlucose()
        #expect(ascending.count == values.count)

        // Split into:
        // - older block (before gap)
        // - recent block (after gap)
        let olderBlock = ascending.prefix(10)
        let recentBlock = ascending.suffix(3)

        // --- ASSERT 1: Older values should NOT be overwritten ---
        for (index, obj) in olderBlock.enumerated() {
            #expect(
                obj.smoothedGlucose == nil,
                "Older value at index \(index) should remain untouched (no fallback overwrite)."
            )
        }

        // --- ASSERT 2: Recent values should be filled by fallback ---
        for (index, obj) in recentBlock.enumerated() {
            guard let smoothed = obj.smoothedGlucose?.decimalValue else {
                #expect(false, "Recent value at index \(index) should have smoothedGlucose set.")
                continue
            }

            #expect(
                smoothed >= 39,
                "Fallback smoothed glucose must be clamped to >= 39, got \(smoothed)."
            )

            #expect(
                smoothed == smoothed.rounded(toPlaces: 0),
                "Fallback smoothed glucose must be rounded to integer, got \(smoothed)."
            )
        }
    }

    @Test(
        "Exponential smoothing treats 38 mg/dL as xDrip error and clamps stored smoothed glucose"
    ) func testExponentialSmoothingXDrip38StopsWindow() async throws {
        // GIVEN
        let values: [Int16] = [100, 105, 110, 38, 120, 125]
        await createGlucoseSequence(values: values, interval: 5 * 60, isManual: false)

        // WHEN
        await fetchGlucoseManager.exponentialSmoothingGlucose(context: testContext)

        // THEN
        let ascending = try await fetchAndSortGlucose()
        #expect(ascending.count == 6)

        let smoothedValues = ascending
            .compactMap { $0.smoothedGlucose?.decimalValue }
            .filter { $0 > 0 }

        #expect(
            !smoothedValues.isEmpty,
            "Expected at least one smoothed glucose value to be stored."
        )

        for (index, smoothed) in smoothedValues.enumerated() {
            #expect(
                smoothed >= 39,
                "Smoothed glucose must be clamped to >= 39 even around xDrip 38, got \(smoothed) at index \(index)."
            )
            #expect(
                smoothed == smoothed.rounded(toPlaces: 0),
                "Smoothed glucose must be rounded to an integer, got \(smoothed) at index \(index)."
            )
        }
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
