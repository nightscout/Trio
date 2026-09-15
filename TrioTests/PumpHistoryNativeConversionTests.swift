import CoreData
import Foundation
import Testing

@testable import Trio

/// Golden tests certifying that the native `PumpEventStored` → `[PumpHistoryEvent]` mapping
/// (`OpenAPS.nativePumpHistory` / `PumpEventStored.toPumpHistoryEvents`) reproduces, field for
/// field, the pump history the algorithm used to receive through the old JSON round-trip
/// (`PumpEventStored` → `[PumpEventDTO]` → JSON → `JSONBridge.pumpHistory`) — with one deliberate
/// change: a nil `tempType` becomes `temp = nil` instead of throwing during decode.
@Suite("Pump History Native Conversion Tests", .serialized) struct PumpHistoryNativeConversionTests {
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

    init() async throws {
        coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()
    }

    // MARK: - Golden tests (native mapping vs frozen old-path output)

    @Test("A bolus maps identically") func testBolus() async throws {
        let ids = [
            try await insertBolus(id: uuid(1), date: fixedDate(0), amount: 2.5, isSMB: true, isExternal: false)
        ]
        try await assertNativeMatchesGolden(ids, golden: [
            PumpHistoryEvent(
                id: uuid(1),
                type: .bolus,
                timestamp: fixedDate(0),
                amount: dec("2.5"),
                duration: 0,
                isSMB: true,
                isExternal: false
            )
        ])
    }

    @Test("An external, non-SMB bolus maps identically") func testExternalBolus() async throws {
        let ids = [
            try await insertBolus(id: uuid(1), date: fixedDate(0), amount: 0.88, isSMB: false, isExternal: true)
        ]
        // 0.88 stored as a Core Data Decimal round-trips through the lossy Double hop to
        // 0.8800000000000001; the golden freezes that coerced value.
        try await assertNativeMatchesGolden(ids, golden: [
            PumpHistoryEvent(
                id: uuid(1),
                type: .bolus,
                timestamp: fixedDate(0),
                amount: dec("0.8800000000000001"),
                duration: 0,
                isSMB: false,
                isExternal: true
            )
        ])
    }

    @Test("A temp basal emits a duration entry then a rate entry, both identical") func testTempBasal() async throws {
        let ids = [
            try await insertTempBasal(id: uuid(1), date: fixedDate(0), rate: 0.85, durationMinutes: 30, tempType: "absolute")
        ]
        let native = try await nativeEvents(ids)
        // Exactly two entries, ordered duration-then-rate.
        #expect(native.count == 2)
        #expect(native.first?.type == .tempBasalDuration)
        #expect(native.first?.durationMin == 30)
        #expect(native.first?.duration == nil, "the duration entry uses durationMin, never duration")
        #expect(native.last?.type == .tempBasal)
        #expect(native.last?.id == "_\(uuid(1))", "the rate entry id is prefixed with an underscore")
        #expect(native.last?.temp == .absolute)
        try await assertNativeMatchesGolden(ids, golden: [
            PumpHistoryEvent(id: uuid(1), type: .tempBasalDuration, timestamp: fixedDate(0), durationMin: 30),
            PumpHistoryEvent(id: "_\(uuid(1))", type: .tempBasal, timestamp: fixedDate(0), rate: dec("0.85"), temp: .absolute)
        ])
    }

    @Test("A percent temp basal maps identically") func testPercentTempBasal() async throws {
        let ids = [
            try await insertTempBasal(id: uuid(1), date: fixedDate(0), rate: 1.5, durationMinutes: 45, tempType: "percent")
        ]
        try await assertNativeMatchesGolden(ids, golden: [
            PumpHistoryEvent(id: uuid(1), type: .tempBasalDuration, timestamp: fixedDate(0), durationMin: 45),
            PumpHistoryEvent(id: "_\(uuid(1))", type: .tempBasal, timestamp: fixedDate(0), rate: dec("1.5"), temp: .percent)
        ])
    }

    @Test("A temp basal with a nil rate emits only the duration entry") func testTempBasalNilRate() async throws {
        let ids = [
            try await insertTempBasal(id: uuid(1), date: fixedDate(0), rate: nil, durationMinutes: 30, tempType: "absolute")
        ]
        try await assertNativeMatchesGolden(ids, golden: [
            PumpHistoryEvent(id: uuid(1), type: .tempBasalDuration, timestamp: fixedDate(0), durationMin: 30)
        ])
    }

    @Test("Suspend, resume, rewind and prime map identically") func testStatusEvents() async throws {
        let ids = [
            try await insertStatusEvent(id: uuid(1), date: fixedDate(0), type: .pumpSuspend),
            try await insertStatusEvent(id: uuid(2), date: fixedDate(1), type: .pumpResume),
            try await insertStatusEvent(id: uuid(3), date: fixedDate(2), type: .rewind),
            try await insertStatusEvent(id: uuid(4), date: fixedDate(3), type: .prime)
        ]
        try await assertNativeMatchesGolden(ids, golden: [
            PumpHistoryEvent(id: uuid(1), type: .pumpSuspend, timestamp: fixedDate(0)),
            PumpHistoryEvent(id: uuid(2), type: .pumpResume, timestamp: fixedDate(1)),
            PumpHistoryEvent(id: uuid(3), type: .rewind, timestamp: fixedDate(2)),
            PumpHistoryEvent(id: uuid(4), type: .prime, timestamp: fixedDate(3))
        ])
    }

    @Test("A mixed sequence maps identically") func testMixedSequence() async throws {
        let ids = [
            try await insertBolus(id: uuid(1), date: fixedDate(0), amount: 1.0, isSMB: true, isExternal: false),
            try await insertTempBasal(id: uuid(2), date: fixedDate(1), rate: 0.7, durationMinutes: 30, tempType: "absolute"),
            try await insertStatusEvent(id: uuid(3), date: fixedDate(2), type: .pumpSuspend),
            try await insertStatusEvent(id: uuid(4), date: fixedDate(3), type: .pumpResume),
            try await insertBolus(id: uuid(5), date: fixedDate(4), amount: 0.05, isSMB: true, isExternal: false)
        ]
        try await assertNativeMatchesGolden(ids, golden: [
            PumpHistoryEvent(
                id: uuid(1),
                type: .bolus,
                timestamp: fixedDate(0),
                amount: dec("1.0"),
                duration: 0,
                isSMB: true,
                isExternal: false
            ),
            PumpHistoryEvent(id: uuid(2), type: .tempBasalDuration, timestamp: fixedDate(1), durationMin: 30),
            PumpHistoryEvent(id: "_\(uuid(2))", type: .tempBasal, timestamp: fixedDate(1), rate: dec("0.7"), temp: .absolute),
            PumpHistoryEvent(id: uuid(3), type: .pumpSuspend, timestamp: fixedDate(2)),
            PumpHistoryEvent(id: uuid(4), type: .pumpResume, timestamp: fixedDate(3)),
            PumpHistoryEvent(
                id: uuid(5),
                type: .bolus,
                timestamp: fixedDate(4),
                amount: dec("0.05"),
                duration: 0,
                isSMB: true,
                isExternal: false
            )
        ])
    }

    @Test("Orphaned resumes are filtered") func testOrphanedResumeFiltering() async throws {
        let bolus = try await insertBolus(id: uuid(1), date: fixedDate(0), amount: 1.0, isSMB: true, isExternal: false)
        let orphanedResume = try await insertStatusEvent(id: uuid(2), date: fixedDate(1), type: .pumpResume)
        let ids = [bolus, orphanedResume]

        try await assertNativeMatchesGolden(ids, orphanedResumes: [orphanedResume], golden: [
            PumpHistoryEvent(
                id: uuid(1),
                type: .bolus,
                timestamp: fixedDate(0),
                amount: dec("1.0"),
                duration: 0,
                isSMB: true,
                isExternal: false
            )
        ])
    }

    @Test("Empty history maps to an empty array") func testEmpty() async throws {
        try await assertNativeMatchesGolden([], golden: [])
    }

    // MARK: - The one deliberate behavioral change

    @Test("A nil tempType becomes temp = nil instead of throwing") func testNilTempTypeIsRobust() async throws {
        let ids = [
            try await insertTempBasal(id: uuid(1), date: fixedDate(0), rate: 0.85, durationMinutes: 30, tempType: nil)
        ]
        // The old JSON path emitted the string "unknown" for a nil tempType, which threw while
        // decoding. Native emits both entries and leaves temp nil instead.
        try await assertNativeMatchesGolden(ids, golden: [
            PumpHistoryEvent(id: uuid(1), type: .tempBasalDuration, timestamp: fixedDate(0), durationMin: 30),
            PumpHistoryEvent(id: "_\(uuid(1))", type: .tempBasal, timestamp: fixedDate(0), rate: dec("0.85"), temp: nil)
        ])
    }

    // MARK: - Comparison helpers

    /// Asserts the native mapping reproduces the frozen golden `[PumpHistoryEvent]`.
    private func assertNativeMatchesGolden(
        _ objectIDs: [NSManagedObjectID],
        orphanedResumes: [NSManagedObjectID] = [],
        golden: [PumpHistoryEvent]
    ) async throws {
        let native = try await nativeEvents(objectIDs, orphanedResumes: orphanedResumes)

        #expect(native.count == golden.count, "native produced \(native.count) events, golden has \(golden.count)")

        for (index, pair) in zip(native, golden).enumerated() {
            expectFieldsEqual(pair.0, pair.1, event: index)
        }
    }

    private func nativeEvents(
        _ objectIDs: [NSManagedObjectID],
        orphanedResumes: [NSManagedObjectID] = []
    ) async throws -> [PumpHistoryEvent] {
        try await testContext.perform {
            OpenAPS.nativePumpHistory(objectIDs, orphanedResumes: orphanedResumes, from: self.testContext)
        }
    }

    /// Field-by-field comparison, comparing `timestamp` at millisecond resolution.
    private func expectFieldsEqual(_ actual: PumpHistoryEvent, _ expected: PumpHistoryEvent, event index: Int) {
        #expect(actual.id == expected.id, "event \(index): id \(actual.id) != \(expected.id)")
        #expect(actual.type == expected.type, "event \(index): type \(actual.type) != \(expected.type)")
        #expect(
            Self.millisecondString(actual.timestamp) == Self.millisecondString(expected.timestamp),
            "event \(index): timestamp mismatch"
        )
        #expect(actual.amount == expected.amount, "event \(index): amount \(desc(actual.amount)) != \(desc(expected.amount))")
        #expect(
            actual.duration == expected.duration,
            "event \(index): duration \(desc(actual.duration)) != \(desc(expected.duration))"
        )
        #expect(
            actual.durationMin == expected.durationMin,
            "event \(index): durationMin \(desc(actual.durationMin)) != \(desc(expected.durationMin))"
        )
        #expect(actual.rate == expected.rate, "event \(index): rate \(desc(actual.rate)) != \(desc(expected.rate))")
        #expect(actual.temp == expected.temp, "event \(index): temp \(desc(actual.temp)) != \(desc(expected.temp))")
        #expect(actual.isSMB == expected.isSMB, "event \(index): isSMB \(desc(actual.isSMB)) != \(desc(expected.isSMB))")
        #expect(
            actual.isExternal == expected.isExternal,
            "event \(index): isExternal \(desc(actual.isExternal)) != \(desc(expected.isExternal))"
        )
    }

    private func desc<T>(_ value: T?) -> String { value.map { "\($0)" } ?? "nil" }

    /// Builds a `Decimal` from its string form, matching `Decimal(algorithmValue:)`.
    private func dec(_ string: String) -> Decimal { Decimal(string: string) ?? .zero }

    private static func millisecondString(_ date: Date) -> String {
        Formatter.iso8601withFractionalSeconds.string(from: date)
    }

    // MARK: - Fixture helpers

    private func insertBolus(
        id: String,
        date: Date,
        amount: Double,
        isSMB: Bool,
        isExternal: Bool
    ) async throws -> NSManagedObjectID {
        try await testContext.perform {
            let event = PumpEventStored(context: self.testContext)
            event.id = id
            event.timestamp = date
            event.type = PumpEventStored.EventType.bolus.rawValue

            let bolus = BolusStored(context: self.testContext)
            bolus.amount = NSDecimalNumber(value: amount)
            bolus.isSMB = isSMB
            bolus.isExternal = isExternal
            bolus.pumpEvent = event

            try self.testContext.save()
            return event.objectID
        }
    }

    private func insertTempBasal(
        id: String,
        date: Date,
        rate: Double?,
        durationMinutes: Int,
        tempType: String?
    ) async throws -> NSManagedObjectID {
        try await testContext.perform {
            let event = PumpEventStored(context: self.testContext)
            event.id = id
            event.timestamp = date
            event.type = PumpEventStored.EventType.tempBasal.rawValue

            let tempBasal = TempBasalStored(context: self.testContext)
            tempBasal.rate = rate.map { NSDecimalNumber(value: $0) }
            tempBasal.duration = Int16(durationMinutes)
            tempBasal.tempType = tempType
            tempBasal.pumpEvent = event

            try self.testContext.save()
            return event.objectID
        }
    }

    private func insertStatusEvent(
        id: String,
        date: Date,
        type: PumpEventStored.EventType
    ) async throws -> NSManagedObjectID {
        try await testContext.perform {
            let event = PumpEventStored(context: self.testContext)
            event.id = id
            event.timestamp = date
            event.type = type.rawValue
            try self.testContext.save()
            return event.objectID
        }
    }

    /// A fixed base timestamp on whole seconds so fixtures are deterministic.
    private func fixedDate(_ minutesAgo: Double) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 - minutesAgo * 60)
    }

    private func uuid(_ n: Int) -> String {
        String(format: "00000000-0000-0000-0000-%012d", n)
    }
}
