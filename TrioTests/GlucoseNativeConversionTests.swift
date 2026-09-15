import CoreData
import Foundation
import Testing

@testable import Trio

/// Golden tests certifying that the native `GlucoseStored` → `BloodGlucose` mapping
/// (`BaseGlucoseStorage.mapToBloodGlucose`) reproduces, byte for byte, the glucose the algorithm used to
/// receive through the old JSON round-trip (`GlucoseStored` → `AlgorithmGlucose` → JSON →
/// `JSONBridge.glucose`). The golden literals below were captured from that old path while it
/// still existed (via a temporary differential run), so a match proves the algorithm still sees
/// identical inputs now that the JSON round-trip is gone.
///
/// The comparison is field by field (see `expectFieldsEqual`), NOT `==`: `BloodGlucose.==` only
/// compares `dateString`, so a plain array comparison would pass even if
/// `glucose`/`sgv`/`direction`/`id`/`type` differed — exactly the coerced fields this migration
/// must preserve.
///
/// Fixtures use fixed dates and ids so the mapping is fully deterministic and independent of the
/// wall-clock-relative time-window fetch (which is unchanged by this migration and stays covered
/// by `GlucoseSmoothingTests`).
@Suite("Glucose Native Conversion Tests", .serialized) struct GlucoseNativeConversionTests {
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

    init() async throws {
        coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()
    }

    // MARK: - Golden tests (native mapping vs frozen old-path output)

    @Test("CGM readings without smoothing map identically") func testCGMNoSmoothing() async throws {
        await insertGlucose(glucose: 120, isManual: false, date: fixedDate(minutesAgo: 0), direction: "Flat", id: uuid(1))
        await insertGlucose(glucose: 95, isManual: false, date: fixedDate(minutesAgo: 5), direction: "FortyFiveDown", id: uuid(2))
        await insertGlucose(glucose: 150, isManual: true, date: fixedDate(minutesAgo: 10), direction: nil, id: uuid(3))

        try await assertNativeMatchesGolden(shouldSmoothGlucose: false, [
            BloodGlucose(
                id: uuid(1).uuidString,
                sgv: 120,
                direction: .flat,
                date: 1_700_000_000_000,
                dateString: Date(timeIntervalSince1970: 1_700_000_000),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(2).uuidString,
                sgv: 95,
                direction: .fortyFiveDown,
                date: 1_699_999_700_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_700),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(3).uuidString,
                date: 1_699_999_400_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_400),
                glucose: 150,
                type: "sgv"
            )
        ])
    }

    @Test("Smoothed CGM value is used and rounded identically") func testSmoothedValueUsed() async throws {
        await insertGlucose(
            glucose: 120,
            isManual: false,
            date: fixedDate(minutesAgo: 0),
            smoothed: Decimal(string: "118.6"),
            direction: "Flat",
            id: uuid(1)
        )

        try await assertNativeMatchesGolden(shouldSmoothGlucose: true, [
            BloodGlucose(
                id: uuid(1).uuidString,
                sgv: 119,
                direction: .flat,
                date: 1_700_000_000_000,
                dateString: Date(timeIntervalSince1970: 1_700_000_000),
                type: "sgv"
            )
        ])

        let native = try await nativeBloodGlucose(shouldSmoothGlucose: true)
        #expect(native.first?.sgv == 119, "118.6 should round to 119 in the sgv field")
        #expect(native.first?.glucose == nil, "CGM readings must not populate the manual `glucose` field")
    }

    @Test("Zero smoothed value falls back to the raw value") func testSmoothedZeroFallsBackToRaw() async throws {
        await insertGlucose(
            glucose: 120,
            isManual: false,
            date: fixedDate(minutesAgo: 0),
            smoothed: 0,
            direction: "Flat",
            id: uuid(1)
        )

        try await assertNativeMatchesGolden(shouldSmoothGlucose: true, [
            BloodGlucose(
                id: uuid(1).uuidString,
                sgv: 120,
                direction: .flat,
                date: 1_700_000_000_000,
                dateString: Date(timeIntervalSince1970: 1_700_000_000),
                type: "sgv"
            )
        ])

        let native = try await nativeBloodGlucose(shouldSmoothGlucose: true)
        #expect(native.first?.sgv == 120, "A zero smoothed value must fall back to the raw 120")
    }

    @Test("Nil smoothed value falls back to the raw value") func testSmoothedNilFallsBackToRaw() async throws {
        await insertGlucose(
            glucose: 120,
            isManual: false,
            date: fixedDate(minutesAgo: 0),
            smoothed: nil,
            direction: "Flat",
            id: uuid(1)
        )

        try await assertNativeMatchesGolden(shouldSmoothGlucose: true, [
            BloodGlucose(
                id: uuid(1).uuidString,
                sgv: 120,
                direction: .flat,
                date: 1_700_000_000_000,
                dateString: Date(timeIntervalSince1970: 1_700_000_000),
                type: "sgv"
            )
        ])

        let native = try await nativeBloodGlucose(shouldSmoothGlucose: true)
        #expect(native.first?.sgv == 120, "A nil smoothed value must fall back to the raw 120")
    }

    @Test("Manual entries ignore smoothing and populate the glucose field") func testManualIgnoresSmoothing() async throws {
        await insertGlucose(
            glucose: 150,
            isManual: true,
            date: fixedDate(minutesAgo: 0),
            smoothed: 140,
            direction: nil,
            id: uuid(1)
        )

        try await assertNativeMatchesGolden(shouldSmoothGlucose: true, [
            BloodGlucose(
                id: uuid(1).uuidString,
                date: 1_700_000_000_000,
                dateString: Date(timeIntervalSince1970: 1_700_000_000),
                glucose: 150,
                type: "sgv"
            )
        ])

        let native = try await nativeBloodGlucose(shouldSmoothGlucose: true)
        #expect(native.first?.glucose == 150, "Manual entries must use the raw value in the `glucose` field")
        #expect(native.first?.sgv == nil, "Manual entries must not populate the `sgv` field")
    }

    @Test("Direction variants and nil map identically") func testDirectionVariants() async throws {
        await insertGlucose(glucose: 110, isManual: false, date: fixedDate(minutesAgo: 0), direction: "TripleUp", id: uuid(1))
        await insertGlucose(glucose: 111, isManual: false, date: fixedDate(minutesAgo: 5), direction: "FortyFiveUp", id: uuid(2))
        await insertGlucose(glucose: 112, isManual: false, date: fixedDate(minutesAgo: 10), direction: "NONE", id: uuid(3))
        await insertGlucose(glucose: 113, isManual: false, date: fixedDate(minutesAgo: 15), direction: nil, id: uuid(4))

        try await assertNativeMatchesGolden(shouldSmoothGlucose: false, [
            BloodGlucose(
                id: uuid(1).uuidString,
                sgv: 110,
                direction: .tripleUp,
                date: 1_700_000_000_000,
                dateString: Date(timeIntervalSince1970: 1_700_000_000),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(2).uuidString,
                sgv: 111,
                direction: .fortyFiveUp,
                date: 1_699_999_700_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_700),
                type: "sgv"
            ),
            // `.none` here is BloodGlucose.Direction.none ("NONE"), not Optional.none — spell it out.
            BloodGlucose(
                id: uuid(3).uuidString,
                sgv: 112,
                direction: BloodGlucose.Direction.none,
                date: 1_699_999_400_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_400),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(4).uuidString,
                sgv: 113,
                date: 1_699_999_100_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_100),
                type: "sgv"
            )
        ])
    }

    @Test("Sub-millisecond dates are truncated identically") func testMillisecondTruncation() async throws {
        // A date with sub-millisecond precision: the old path round-trips it through an ISO8601
        // fractional-seconds string (millisecond precision), so both fields must be ms-truncated.
        await insertGlucose(
            glucose: 100,
            isManual: false,
            date: fixedDate(minutesAgo: 0, plusSeconds: 0.123_456),
            direction: "Flat",
            id: uuid(1)
        )

        try await assertNativeMatchesGolden(shouldSmoothGlucose: false, [
            BloodGlucose(
                id: uuid(1).uuidString,
                sgv: 100,
                direction: .flat,
                date: 1_700_000_000_123,
                dateString: Date(timeIntervalSince1970: 1_700_000_000.123),
                type: "sgv"
            )
        ])
    }

    @Test("A descending multi-entry sequence maps identically") func testDescendingSequence() async throws {
        for i in 0 ..< 6 {
            await insertGlucose(
                glucose: Int16(100 + i),
                isManual: false,
                date: fixedDate(minutesAgo: Double(i) * 5),
                direction: "Flat",
                id: uuid(i + 1)
            )
        }

        try await assertNativeMatchesGolden(shouldSmoothGlucose: false, [
            BloodGlucose(
                id: uuid(1).uuidString,
                sgv: 100,
                direction: .flat,
                date: 1_700_000_000_000,
                dateString: Date(timeIntervalSince1970: 1_700_000_000),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(2).uuidString,
                sgv: 101,
                direction: .flat,
                date: 1_699_999_700_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_700),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(3).uuidString,
                sgv: 102,
                direction: .flat,
                date: 1_699_999_400_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_400),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(4).uuidString,
                sgv: 103,
                direction: .flat,
                date: 1_699_999_100_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_100),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(5).uuidString,
                sgv: 104,
                direction: .flat,
                date: 1_699_998_800_000,
                dateString: Date(timeIntervalSince1970: 1_699_998_800),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(6).uuidString,
                sgv: 105,
                direction: .flat,
                date: 1_699_998_500_000,
                dateString: Date(timeIntervalSince1970: 1_699_998_500),
                type: "sgv"
            )
        ])
    }

    @Test("Smoothing rounding boundaries map identically") func testRoundingBoundaries() async throws {
        await insertGlucose(
            glucose: 100,
            isManual: false,
            date: fixedDate(minutesAgo: 0),
            smoothed: Decimal(string: "118.5"),
            id: uuid(1)
        )
        await insertGlucose(
            glucose: 100,
            isManual: false,
            date: fixedDate(minutesAgo: 5),
            smoothed: Decimal(string: "118.4"),
            id: uuid(2)
        )
        await insertGlucose(
            glucose: 100,
            isManual: false,
            date: fixedDate(minutesAgo: 10),
            smoothed: Decimal(string: "119.5"),
            id: uuid(3)
        )

        try await assertNativeMatchesGolden(shouldSmoothGlucose: true, [
            BloodGlucose(
                id: uuid(1).uuidString,
                sgv: 119,
                date: 1_700_000_000_000,
                dateString: Date(timeIntervalSince1970: 1_700_000_000),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(2).uuidString,
                sgv: 118,
                date: 1_699_999_700_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_700),
                type: "sgv"
            ),
            BloodGlucose(
                id: uuid(3).uuidString,
                sgv: 120,
                date: 1_699_999_400_000,
                dateString: Date(timeIntervalSince1970: 1_699_999_400),
                type: "sgv"
            )
        ])

        let native = try await nativeBloodGlucose(shouldSmoothGlucose: true)
        #expect(native.map(\.sgv) == [119, 118, 120], ".plain scale-0 rounding: 118.5→119, 118.4→118, 119.5→120")
    }

    // MARK: - Comparison helpers

    /// Asserts the native mapping reproduces the frozen golden `BloodGlucose` values. The goldens
    /// were captured from the old `AlgorithmGlucose` → JSON → `JSONBridge.glucose` path (see the
    /// differential run in this migration's history), so a match proves the algorithm still receives
    /// identical glucose after the JSON round-trip was removed.
    private func assertNativeMatchesGolden(shouldSmoothGlucose: Bool, _ golden: [BloodGlucose]) async throws {
        let native = try await nativeBloodGlucose(shouldSmoothGlucose: shouldSmoothGlucose)

        #expect(native.count == golden.count, "native produced \(native.count) entries, golden has \(golden.count)")

        for (index, pair) in zip(native, golden).enumerated() {
            expectFieldsEqual(pair.0, pair.1, entry: index)
        }
    }

    /// Field-by-field comparison. We can't use `==`: `BloodGlucose.==` only compares `dateString`,
    /// so a direct comparison would pass even if `sgv`/`glucose`/`direction`/`id`/`type` differed —
    /// exactly the coerced fields we must pin.
    ///
    /// `dateString` is compared at millisecond resolution rather than as an exact `Date`. The mapping
    /// keeps the reading's full-precision date in memory, but only millisecond precision is ever
    /// observable — it's what `date` pins and what the value serializes to — and Core Data's `Double`
    /// round-trip perturbs sub-millisecond bits anyway, so an exact `Date` comparison would be flaky.
    private func expectFieldsEqual(_ actual: BloodGlucose, _ expected: BloodGlucose, entry index: Int) {
        #expect(actual.id == expected.id, "entry \(index): id \(actual.id) != \(expected.id)")
        #expect(actual.legacyId == expected.legacyId, "entry \(index): legacyId")
        #expect(
            actual.sgv == expected.sgv,
            "entry \(index): sgv \(actual.sgv.map(String.init) ?? "nil") != \(expected.sgv.map(String.init) ?? "nil")"
        )
        #expect(
            actual.glucose == expected.glucose,
            "entry \(index): glucose \(actual.glucose.map(String.init) ?? "nil") != \(expected.glucose.map(String.init) ?? "nil")"
        )
        #expect(actual.mbg == expected.mbg, "entry \(index): mbg")
        #expect(
            actual.direction == expected.direction,
            "entry \(index): direction \(actual.direction?.rawValue ?? "nil") != \(expected.direction?.rawValue ?? "nil")"
        )
        #expect(actual.date == expected.date, "entry \(index): date \(actual.date) != \(expected.date)")
        #expect(
            Self.millisecondString(actual.dateString) == Self.millisecondString(expected.dateString),
            "entry \(index): dateString \(Self.millisecondString(actual.dateString)) != \(Self.millisecondString(expected.dateString))"
        )
        #expect(actual.type == expected.type, "entry \(index): type \(actual.type ?? "nil") != \(expected.type ?? "nil")")
        #expect(actual.unfiltered == expected.unfiltered, "entry \(index): unfiltered")
        #expect(actual.filtered == expected.filtered, "entry \(index): filtered")
        #expect(actual.noise == expected.noise, "entry \(index): noise")
        #expect(actual.activationDate == expected.activationDate, "entry \(index): activationDate")
        #expect(actual.sessionStartDate == expected.sessionStartDate, "entry \(index): sessionStartDate")
        #expect(actual.transmitterID == expected.transmitterID, "entry \(index): transmitterID")
    }

    private static func millisecondString(_ date: Date) -> String {
        Formatter.iso8601withFractionalSeconds.string(from: date)
    }

    private func nativeBloodGlucose(shouldSmoothGlucose: Bool) async throws -> [BloodGlucose] {
        try await testContext.perform {
            try self.fetchRowsNewestFirst().map {
                BaseGlucoseStorage.mapToBloodGlucose(
                    $0,
                    shouldSmoothGlucose: shouldSmoothGlucose,
                    roundingBehavior: Self.roundingBehavior
                )
            }
        }
    }

    /// Must be called from within `testContext.perform`.
    private func fetchRowsNewestFirst() throws -> [GlucoseStored] {
        let request = GlucoseStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try testContext.fetch(request)
    }

    private static let roundingBehavior = NSDecimalNumberHandler(
        roundingMode: .plain,
        scale: 0,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    // MARK: - Fixture helpers

    private func insertGlucose(
        glucose: Int16,
        isManual: Bool,
        date: Date,
        smoothed: Decimal? = nil,
        direction: String? = nil,
        id: UUID
    ) async {
        await testContext.perform {
            let object = GlucoseStored(context: self.testContext)
            object.glucose = glucose
            object.isManual = isManual
            object.date = date
            object.smoothedGlucose = smoothed.map { NSDecimalNumber(decimal: $0) }
            object.direction = direction
            object.id = id
            try! self.testContext.save()
        }
    }

    /// A fixed base timestamp (2023-11-14T22:13:20Z) so fixtures are deterministic and reproducible.
    private func fixedDate(minutesAgo: Double, plusSeconds: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + plusSeconds - minutesAgo * 60)
    }

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }
}
