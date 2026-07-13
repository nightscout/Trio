import CoreData
import Foundation
import Swinject
import Testing

@testable import LoopKit
@testable import Trio

/// Verifies the scheduled-basal reconciler: gaps no pump reports are filled
/// from the basal profile, reported data always wins, suspensions are never
/// backfilled — including a suspend that started before the lookback window.
@Suite("Scheduled Basal Reconciler Tests", .serialized) struct ScheduledBasalReconcilerTests: Injectable {
    @Injected() var storage: PumpHistoryStorage!
    @Injected() var fileStorage: FileStorage!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!
    typealias PumpEvent = PumpEventStored.EventType

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
    }

    private var reconciler: BasePumpHistoryStorage {
        storage as! BasePumpHistoryStorage
    }

    // MARK: - Fixtures

    private var flatProfile: [BasalProfileEntry] {
        [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0)]
    }

    private func setProfile(_ entries: [BasalProfileEntry]) {
        fileStorage.save(entries, as: OpenAPS.Settings.basalProfile)
    }

    // startOfDay-anchored so all times share one calendar day, matching the reconciler's boundary math
    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private func insertReportedTempBasal(start: Date, end: Date, rate: Decimal) async throws {
        try await testContext.perform {
            let event = PumpEventStored(context: testContext)
            event.id = UUID().uuidString
            event.timestamp = start
            event.type = PumpEvent.tempBasal.rawValue
            event.syncIdentifier = UUID().uuidString
            event.isMutable = false
            let tempBasal = TempBasalStored(context: testContext)
            tempBasal.pumpEvent = event
            tempBasal.isScheduledBasal = false
            tempBasal.rate = rate as NSDecimalNumber
            tempBasal.startDate = start
            tempBasal.endDate = end
            tempBasal.duration = Int16(round(end.timeIntervalSince(start) / 60))
            tempBasal.tempType = PumpEventStored.TempType.absolute.rawValue
            try testContext.save()
        }
    }

    private func insertEvent(_ type: PumpEvent, at date: Date) async throws {
        try await testContext.perform {
            let event = PumpEventStored(context: testContext)
            event.id = UUID().uuidString
            event.timestamp = date
            event.type = type.rawValue
            event.isMutable = false
            try testContext.save()
        }
    }

    private struct ScheduledBasalRow {
        let start: Date
        let end: Date
        let rate: Decimal
        let isMutable: Bool
    }

    private func fetchScheduledBasalRows() async throws -> [ScheduledBasalRow] {
        try await testContext.perform {
            let request = PumpEventStored.fetchRequest() as NSFetchRequest<PumpEventStored>
            request.predicate = NSPredicate(format: "tempBasal.isScheduledBasal == YES")
            let rows: [ScheduledBasalRow] = try testContext.fetch(request).compactMap { row in
                guard let temp = row.tempBasal, let start = temp.startDate, let end = temp.endDate else { return nil }
                return ScheduledBasalRow(
                    start: start,
                    end: end,
                    rate: temp.rate as? Decimal ?? -1,
                    isMutable: row.isMutable
                )
            }
            return rows.sorted { $0.start < $1.start }
        }
    }

    private func totalDuration(_ rows: [ScheduledBasalRow]) -> TimeInterval {
        rows.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    private func isContiguous(_ rows: [ScheduledBasalRow]) -> Bool {
        zip(rows, rows.dropFirst()).allSatisfy { abs($0.end.timeIntervalSince($1.start)) < 1 }
    }

    private func near(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 1
    }

    // MARK: - Backfill

    @Test("Gap after last reported temp basal is filled to now") func testFillsGapAfterReportedTempBasal() async throws {
        setProfile(flatProfile)
        let now = time(12)
        try await insertReportedTempBasal(start: time(9), end: time(9, 30), rate: 2.0)

        try await reconciler.reconcileScheduledBasal(now: now)

        let rows = try await fetchScheduledBasalRows()
        #expect(!rows.isEmpty, "Uncovered gap must be backfilled")
        #expect(near(rows.first!.start, time(9, 30)), "Backfill starts where the reported temp basal ends")
        #expect(near(rows.last!.end, now), "Backfill reaches now")
        #expect(isContiguous(rows), "Backfill must not leave holes or overlaps")
        #expect(rows.allSatisfy { $0.rate == 1.0 }, "Rate comes from the profile")
        #expect(rows.last?.isMutable == true, "Trailing segment stays mutable for the next run")
    }

    @Test("Nothing is fabricated before the first reported event") func testNoBackfillBeforeFirstEvent() async throws {
        setProfile(flatProfile)
        try await insertEvent(.bolus, at: time(10))

        try await reconciler.reconcileScheduledBasal(now: time(12))

        let rows = try await fetchScheduledBasalRows()
        #expect(rows.allSatisfy { $0.start >= time(10) }, "History before the first event is unknowable")
    }

    @Test("Empty store yields no synthetic rows") func testNoEventsNoBackfill() async throws {
        setProfile(flatProfile)

        try await reconciler.reconcileScheduledBasal(now: time(12))

        let rows = try await fetchScheduledBasalRows()
        #expect(rows.isEmpty)
    }

    @Test("Missing basal profile disables the reconciler") func testNoProfileNoBackfill() async throws {
        fileStorage.remove(OpenAPS.Settings.basalProfile)
        try await insertEvent(.bolus, at: time(10))

        try await reconciler.reconcileScheduledBasal(now: time(12))

        let rows = try await fetchScheduledBasalRows()
        #expect(rows.isEmpty)
    }

    @Test("Segments split at schedule boundaries with per-segment rates") func testSplitsAtScheduleBoundary() async throws {
        setProfile([
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0),
            BasalProfileEntry(start: "06:00", minutes: 360, rate: 2.0)
        ])
        try await insertEvent(.bolus, at: time(5))

        try await reconciler.reconcileScheduledBasal(now: time(7))

        let rows = try await fetchScheduledBasalRows()
        #expect(rows.count == 2, "Gap crossing one boundary yields two segments")
        #expect(near(rows[0].start, time(5)) && near(rows[0].end, time(6)))
        #expect(rows[0].rate == 1.0)
        #expect(rows[0].isMutable == false, "Completed segment is finalized")
        #expect(near(rows[1].start, time(6)) && near(rows[1].end, time(7)))
        #expect(rows[1].rate == 2.0)
        #expect(rows[1].isMutable == true, "Trailing segment stays mutable")
    }

    // MARK: - Suspensions

    @Test("Suspended spans are never backfilled") func testSuspensionNotBackfilled() async throws {
        setProfile(flatProfile)
        try await insertEvent(.bolus, at: time(8))
        try await insertEvent(.pumpSuspend, at: time(9))
        try await insertEvent(.pumpResume, at: time(10))

        try await reconciler.reconcileScheduledBasal(now: time(12))

        let rows = try await fetchScheduledBasalRows()
        let suspended = DateInterval(start: time(9), end: time(10))
        #expect(
            rows.allSatisfy { (suspended.intersection(with: DateInterval(start: $0.start, end: $0.end))?.duration ?? 0) < 1 },
            "No delivery happens while suspended"
        )
        #expect(abs(totalDuration(rows) - 3 * 3600) < 2, "Fill covers the 3 unsuspended hours")
    }

    @Test("An open suspend blocks backfill until now") func testOpenSuspendStopsBackfill() async throws {
        setProfile(flatProfile)
        try await insertEvent(.bolus, at: time(8))
        try await insertEvent(.pumpSuspend, at: time(10))

        try await reconciler.reconcileScheduledBasal(now: time(12))

        let rows = try await fetchScheduledBasalRows()
        #expect(rows.allSatisfy { $0.end <= time(10).addingTimeInterval(1) }, "Nothing after the open suspend")
        #expect(abs(totalDuration(rows) - 2 * 3600) < 2, "Fill covers only the 2 running hours")
    }

    @Test("An open suspend older than the lookback window blocks backfill") func testOpenSuspendBeforeLookbackWindow() async throws {
        setProfile(flatProfile)
        let now = time(12)
        // suspend 25h ago sits outside the 24h fetch window; pump still suspended
        try await insertEvent(.pumpSuspend, at: now.addingTimeInterval(-25 * 3600))
        try await insertEvent(.bolus, at: now.addingTimeInterval(-23 * 3600))

        try await reconciler.reconcileScheduledBasal(now: now)

        let rows = try await fetchScheduledBasalRows()
        #expect(rows.isEmpty, "A suspend straddling the window boundary must still block backfill")
    }

    @Test("A resume older than the lookback window does not block backfill") func testResumeBeforeLookbackWindow() async throws {
        setProfile(flatProfile)
        let now = time(12)
        try await insertEvent(.pumpSuspend, at: now.addingTimeInterval(-26 * 3600))
        try await insertEvent(.pumpResume, at: now.addingTimeInterval(-25 * 3600))
        try await insertEvent(.bolus, at: now.addingTimeInterval(-23 * 3600))

        try await reconciler.reconcileScheduledBasal(now: now)

        let rows = try await fetchScheduledBasalRows()
        #expect(abs(totalDuration(rows) - 23 * 3600) < 2, "Resumed pump backfills from the first event to now")
        #expect(isContiguous(rows))
    }

    // MARK: - Self-healing

    @Test("Reported data supersedes overlapping synthetic rows") func testReportedDataSupersedesSynthetic() async throws {
        setProfile(flatProfile)
        let now = time(12)
        try await insertEvent(.bolus, at: time(8))
        try await reconciler.reconcileScheduledBasal(now: now)

        // a late-arriving pump report overlaps the synthetic fill
        try await insertReportedTempBasal(start: time(9), end: time(10), rate: 0.5)
        try await reconciler.reconcileScheduledBasal(now: now)

        let rows = try await fetchScheduledBasalRows()
        let reported = DateInterval(start: time(9), end: time(10))
        #expect(
            rows.allSatisfy { (reported.intersection(with: DateInterval(start: $0.start, end: $0.end))?.duration ?? 0) < 1 },
            "Synthetic rows must yield to reported data"
        )
        #expect(abs(totalDuration(rows) - 3 * 3600) < 2, "Remaining fill covers the 3 unreported hours")
    }

    @Test("Reconciliation is idempotent") func testReconcileIsIdempotent() async throws {
        setProfile(flatProfile)
        let now = time(12)
        try await insertEvent(.bolus, at: time(8))

        try await reconciler.reconcileScheduledBasal(now: now)
        let firstRun = try await fetchScheduledBasalRows()
        try await reconciler.reconcileScheduledBasal(now: now)
        let secondRun = try await fetchScheduledBasalRows()

        #expect(firstRun.count == secondRun.count, "Repeat runs must not grow the row set")
        #expect(abs(totalDuration(firstRun) - totalDuration(secondRun)) < 2)
        #expect(isContiguous(secondRun))
        #expect(near(secondRun.last!.end, now))
    }
}
