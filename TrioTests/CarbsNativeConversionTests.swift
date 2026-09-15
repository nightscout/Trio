import CoreData
import Foundation
import Testing

@testable import Trio

/// Golden tests certifying that the native `CarbEntryStored` → `CarbsEntry` mapping
/// (`BaseCarbsStorage.mapToCarbsEntry`) reproduces, field for field, the carbs the algorithm used to receive
/// through the old JSON round-trip (`CarbEntryStored` → JSON → `JSONBridge.carbs`) — with one
/// deliberate, documented change: `id`.
@Suite("Carbs Native Conversion Tests", .serialized) struct CarbsNativeConversionTests {
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

    init() async throws {
        coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()
    }

    // MARK: - Golden tests (native mapping vs frozen old-path output)

    @Test("A basic carb entry maps identically (id now populated)") func testBasicEntry() async throws {
        await insertCarb(carbs: 30, isFPU: false, date: fixedDate(minutesAgo: 0), note: "breakfast", id: uuid(1))

        try await assertNativeMatchesGolden([
            CarbsEntry(
                id: uuid(1).uuidString,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                actualDate: Date(timeIntervalSince1970: 1_700_000_000),
                carbs: 30,
                fat: 0,
                protein: 0,
                note: nil, // old path decoded "note" as "notes" → nil; preserved
                enteredBy: CarbsEntry.local,
                isFPU: false,
                fpuID: nil
            )
        ])
    }

    @Test("Fractional carbs/fat/protein keep clean decimal values") func testFractionalDecimals() async throws {
        // 33.33 as a Double is 33.32999999999999488; the old JSON round-trip recovered the clean
        // 33.33 (JSONEncoder writes the shortest round-trippable string). `Decimal(Double)` would
        // leak the binary expansion, so `Decimal(algorithmValue:)` must reproduce the clean value.
        await insertCarb(carbs: 33.33, isFPU: true, date: fixedDate(minutesAgo: 0), fat: 5.5, protein: 3.2, id: uuid(1))
        await insertCarb(carbs: 12.5, isFPU: false, date: fixedDate(minutesAgo: 5), id: uuid(2))

        try await assertNativeMatchesGolden([
            CarbsEntry(
                id: uuid(1).uuidString,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                actualDate: Date(timeIntervalSince1970: 1_700_000_000),
                carbs: Decimal(string: "33.33")!,
                fat: Decimal(string: "5.5")!,
                protein: Decimal(string: "3.2")!,
                note: nil,
                enteredBy: CarbsEntry.local,
                isFPU: true,
                fpuID: nil
            ),
            CarbsEntry(
                id: uuid(2).uuidString,
                createdAt: Date(timeIntervalSince1970: 1_699_999_700),
                actualDate: Date(timeIntervalSince1970: 1_699_999_700),
                carbs: Decimal(string: "12.5")!,
                fat: 0,
                protein: 0,
                note: nil,
                enteredBy: CarbsEntry.local,
                isFPU: false,
                fpuID: nil
            )
        ])

        let native = try await nativeCarbsEntries()
        #expect(native.first?.carbs == Decimal(string: "33.33")!, "33.33 must stay clean, not the Double expansion")
    }

    @Test("A zero-carb entry (nil stored id) maps identically") func testZeroCarbNilId() async throws {
        // The old path always produced id == nil, so a stored entry with no id is indistinguishable
        // there. Natively, a nil stored id still maps to a nil `CarbsEntry.id`.
        await insertCarb(carbs: 0, isFPU: false, date: fixedDate(minutesAgo: 0), id: nil)

        try await assertNativeMatchesGolden([
            CarbsEntry(
                id: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                actualDate: Date(timeIntervalSince1970: 1_700_000_000),
                carbs: 0,
                fat: 0,
                protein: 0,
                note: nil,
                enteredBy: CarbsEntry.local,
                isFPU: false,
                fpuID: nil
            )
        ])
    }

    @Test("A multi-entry sequence maps identically") func testMultiEntrySequence() async throws {
        for i in 0 ..< 5 {
            await insertCarb(
                carbs: Double(10 * (i + 1)),
                isFPU: false,
                date: fixedDate(minutesAgo: Double(i) * 5),
                id: uuid(i + 1)
            )
        }

        try await assertNativeMatchesGolden((0 ..< 5).map { i in
            CarbsEntry(
                id: uuid(i + 1).uuidString,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(i) * 300),
                actualDate: Date(timeIntervalSince1970: 1_700_000_000 - Double(i) * 300),
                carbs: Decimal(10 * (i + 1)),
                fat: 0,
                protein: 0,
                note: nil,
                enteredBy: CarbsEntry.local,
                isFPU: false,
                fpuID: nil
            )
        })
    }

    @Test("Sub-millisecond dates are truncated to millisecond resolution") func testMillisecondTruncation() async throws {
        // The old path round-tripped the stored date through an ISO8601 fractional-seconds string
        // (millisecond precision). The native path keeps the full-precision `Date`, but only
        // millisecond precision is ever observable, so the comparison is at ms resolution.
        await insertCarb(carbs: 25, isFPU: false, date: fixedDate(minutesAgo: 0, plusSeconds: 0.123_456), id: uuid(1))

        try await assertNativeMatchesGolden([
            CarbsEntry(
                id: uuid(1).uuidString,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000.123),
                actualDate: Date(timeIntervalSince1970: 1_700_000_000.123),
                carbs: 25,
                fat: 0,
                protein: 0,
                note: nil,
                enteredBy: CarbsEntry.local,
                isFPU: false,
                fpuID: nil
            )
        ])
    }

    // MARK: - The one deliberate behavioral change

    @Test("id is now populated from Core Data (old path always produced nil)") func testIdIsNowPopulatedFromCoreData() async throws {
        await insertCarb(carbs: 40, isFPU: false, date: fixedDate(minutesAgo: 0), id: uuid(7))

        let native = try await nativeCarbsEntries()
        // Old JSON path: `id` was encoded under "id" but decoded from "_id", so this was always nil.
        // The native mapping carries the real Core Data id instead.
        #expect(native.first?.id == uuid(7).uuidString, "native mapping must carry the Core Data id")
    }

    // MARK: - Additional (synthetic) carbs entry

    @Test("The synthetic additional-carbs entry matches the old spliced dictionary") func testAdditionalCarbsEntry() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let id = uuid(99).uuidString
        let entry = BaseCarbsStorage.additionalCarbsEntry(carbs: 15, date: date, id: id)

        // Old path spliced a dictionary that decoded to: id=nil (encoded "id", decoded "_id"),
        // note=nil, fat=0, protein=0, isFPU=false, enteredBy="Trio", both dates == the passed date.
        // The only intended difference is `id`, which we now carry (see `additionalCarbsEntry`).
        let expected = CarbsEntry(
            id: id,
            createdAt: date,
            actualDate: date,
            carbs: 15,
            fat: 0,
            protein: 0,
            note: nil,
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: nil
        )
        expectFieldsEqual(entry, expected, entry: 0)
    }

    @Test("A zero additional-carbs entry (the normal loop case) is well formed") func testAdditionalCarbsZero() {
        // In the normal determine-basal loop `additionalCarbs` is `simulatedCarbsAmount ?? 0`, so a
        // carbs=0 entry is always appended. MealHistory/AutosensGenerator drop carbs <= 0, so it is
        // inert, but we still reproduce the old shape exactly.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = BaseCarbsStorage.additionalCarbsEntry(carbs: 0, date: date, id: uuid(1).uuidString)
        #expect(entry.carbs == 0)
        #expect(entry.isFPU == false)
        #expect(entry.enteredBy == CarbsEntry.local)
    }

    // MARK: - Comparison helpers

    /// Asserts the native mapping reproduces the frozen golden `CarbsEntry` values.
    private func assertNativeMatchesGolden(_ golden: [CarbsEntry]) async throws {
        let native = try await nativeCarbsEntries()

        #expect(native.count == golden.count, "native produced \(native.count) entries, golden has \(golden.count)")

        for (index, pair) in zip(native, golden).enumerated() {
            expectFieldsEqual(pair.0, pair.1, entry: index)
        }
    }

    /// Field-by-field comparison
    private func expectFieldsEqual(_ actual: CarbsEntry, _ expected: CarbsEntry, entry index: Int) {
        #expect(actual.id == expected.id, "entry \(index): id \(actual.id ?? "nil") != \(expected.id ?? "nil")")
        #expect(
            Self.millisecondString(actual.createdAt) == Self.millisecondString(expected.createdAt),
            "entry \(index): createdAt \(Self.millisecondString(actual.createdAt)) != \(Self.millisecondString(expected.createdAt))"
        )
        #expect(
            actual.actualDate.map(Self.millisecondString) == expected.actualDate.map(Self.millisecondString),
            "entry \(index): actualDate mismatch"
        )
        #expect(actual.carbs == expected.carbs, "entry \(index): carbs \(actual.carbs) != \(expected.carbs)")
        #expect(
            actual.fat == expected.fat,
            "entry \(index): fat \(String(describing: actual.fat)) != \(String(describing: expected.fat))"
        )
        #expect(
            actual.protein == expected.protein,
            "entry \(index): protein \(String(describing: actual.protein)) != \(String(describing: expected.protein))"
        )
        #expect(actual.note == expected.note, "entry \(index): note \(actual.note ?? "nil") != \(expected.note ?? "nil")")
        #expect(
            actual.enteredBy == expected.enteredBy,
            "entry \(index): enteredBy \(actual.enteredBy ?? "nil") != \(expected.enteredBy ?? "nil")"
        )
        #expect(
            actual.isFPU == expected.isFPU,
            "entry \(index): isFPU \(String(describing: actual.isFPU)) != \(String(describing: expected.isFPU))"
        )
        #expect(actual.fpuID == expected.fpuID, "entry \(index): fpuID \(actual.fpuID ?? "nil") != \(expected.fpuID ?? "nil")")
    }

    private static func millisecondString(_ date: Date) -> String {
        Formatter.iso8601withFractionalSeconds.string(from: date)
    }

    private func nativeCarbsEntries() async throws -> [CarbsEntry] {
        try await testContext.perform {
            try self.fetchRowsNewestFirst().map { BaseCarbsStorage.mapToCarbsEntry($0) }
        }
    }

    /// Must be called from within `testContext.perform`. Mirrors the `date`-descending order the
    /// production fetch uses (`BaseCarbsStorage.getCarbsForAlgorithm`).
    private func fetchRowsNewestFirst() throws -> [CarbEntryStored] {
        let request = CarbEntryStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try testContext.fetch(request)
    }

    // MARK: - Fixture helpers

    private func insertCarb(
        carbs: Double,
        isFPU: Bool,
        date: Date,
        fat: Double = 0,
        protein: Double = 0,
        note: String? = nil,
        id: UUID?,
        fpuID: UUID? = nil
    ) async {
        await testContext.perform {
            let object = CarbEntryStored(context: self.testContext)
            object.carbs = carbs
            object.isFPU = isFPU
            object.date = date
            object.fat = fat
            object.protein = protein
            object.note = note
            object.id = id
            object.fpuID = fpuID
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
