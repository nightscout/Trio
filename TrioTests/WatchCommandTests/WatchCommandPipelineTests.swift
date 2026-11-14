import Foundation
import Testing

@testable import Trio

@Suite("Watch Command Pipeline Tests") struct WatchCommandPipelineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    let appUUID = UUID()
    let authorization = WatchCommandAuthorization()
    let cache = WatchCommandRequestCache()
    let logs = LogCapture()
    let executions = ExecutionCounter()
    let done = WatchCommandResult.success(.genericSuccess, "Done.")
    let pipeline: WatchCommandPipeline

    init() {
        pipeline = WatchCommandPipeline(
            authorization: authorization,
            cache: cache,
            now: { [clock] in clock.now },
            log: logs.logger
        )
    }

    private func run(
        _ command: String = "carbs:10",
        id: UUID = UUID(),
        app: UUID? = nil,
        age: TimeInterval = 5,
        on pipeline: WatchCommandPipeline? = nil,
        gate: @escaping @Sendable() -> WatchCommandResult? = { nil },
        execute: ((WatchCommandContext) async -> WatchCommandResult)? = nil
    ) async -> WatchCommandResult {
        await (pipeline ?? self.pipeline).run(
            requestID: id,
            appUUID: app ?? appUUID,
            issuedAt: now.addingTimeInterval(-age),
            command: command,
            name: "carbs",
            gate: gate
        ) { context in
            executions.increment()
            guard let execute else { return done }
            return await execute(context)
        }
    }

    /// Executes like a side effect: parks on `gate`, then runs the final check right before writing.
    private func guardedWrite(
        parkingOn gate: TestGate,
        checkingExpiry: Bool = false
    ) -> (WatchCommandContext) async -> WatchCommandResult {
        { [done] context in
            await gate.pass()
            do {
                try context.finalCheck(checkingExpiry: checkingExpiry)()
                return done
            } catch let rejection as WatchCommandRejection {
                return rejection.result
            } catch {
                return .failure("unexpected")
            }
        }
    }

    // MARK: - Registration

    @Test("Pipeline and authorization are registered once for the whole app") func testContainerScoped() {
        let resolver = TrioApp().resolver
        #expect(resolver.resolve(WatchCommandPipeline.self) === resolver.resolve(WatchCommandPipeline.self))
        #expect(resolver.resolve(WatchCommandAuthorization.self) === resolver.resolve(WatchCommandAuthorization.self))
    }

    // MARK: - Freshness

    @Test(
        "Timestamps are accepted from 2 minutes old to 60 seconds ahead",
        arguments: [
            (TimeInterval(120), true),
            (TimeInterval(120.001), false),
            (TimeInterval(-60), true),
            (TimeInterval(-60.001), false),
            (TimeInterval(0), true)
        ]
    ) func testFreshnessWindow(age: TimeInterval, accepted: Bool) async {
        let result = await run(age: age)

        #expect(result.acknowledged == accepted)
        #expect(executions.value == (accepted ? 1 : 0))
    }

    @Test("Expiry is re-checked only where the side effect asks for it") func testExpiryRecheckIsOptIn() async {
        let gate = TestGate()
        let plain = Task { await run(age: 100, execute: guardedWrite(parkingOn: gate)) }
        let strict = Task { await run(age: 100, execute: guardedWrite(parkingOn: gate, checkingExpiry: true)) }
        await gate.waitForArrivals(2)
        clock.advance(by: 30)
        gate.open()

        #expect(await plain.value.acknowledged)
        #expect(await strict.value.message == "Command expired. Please try again.")
    }

    // MARK: - Gates & Revocation

    @Test("A closed gate rejects before execution") func testGateRejects() async {
        let result = await run(gate: { .failure("Off.") })

        #expect(result == .failure("Off."))
        #expect(executions.value == 0)
    }

    @Test("The gate is re-read at the final check") func testGateRereadAtFinalCheck() async {
        let isOff = TestFlag()
        let gate = TestGate()
        let pending = Task { await run(gate: { isOff.value ? .failure("Off.") : nil }, execute: guardedWrite(parkingOn: gate)) }
        await gate.waitForArrivals()
        isOff.set()
        gate.open()

        #expect(await pending.value == .failure("Off."))
    }

    @Test("A revocation while pending fails the final check, even if switched back on") func testRevokedWhilePending() async {
        let gate = TestGate()
        let pending = Task { await run(execute: guardedWrite(parkingOn: gate)) }
        await gate.waitForArrivals()
        authorization.revoke()
        gate.open()

        let result = await pending.value
        #expect(!result.acknowledged)
        #expect(result.message == "Watch command settings changed.")
        #expect(await run().acknowledged, "A command admitted after the revocation runs")
    }

    // MARK: - Deduplication

    @Test("A completed duplicate replays its result without executing again") func testCompletedDuplicate() async {
        let id = UUID()
        let first = await run(id: id)
        let second = await run(id: id)

        #expect(first == second)
        #expect(executions.value == 1)
    }

    @Test("Rejections are cached as terminal results too") func testRejectionCached() async {
        let id = UUID()
        let first = await run(id: id, gate: { .failure("Off.") })
        let second = await run(id: id)

        #expect(first == second)
        #expect(executions.value == 0)
    }

    @Test("A duplicate of an in-flight request is rejected with the in-progress code") func testInFlightDuplicate() async {
        let gate = TestGate()
        let id = UUID()
        let pending = Task { await run(id: id, execute: guardedWrite(parkingOn: gate)) }
        await gate.waitForArrivals()

        let duplicate = await run(id: id)
        gate.open()

        #expect(!duplicate.acknowledged)
        #expect(duplicate.ackCode == .inProgress, "Watches tell a running duplicate apart by code, not by text")
        #expect(await pending.value.acknowledged)
        #expect(executions.value == 1)
    }

    @Test("Reusing a request ID for another command is rejected") func testConflict() async {
        let id = UUID()
        _ = await run("carbs:10", id: id)
        let result = await run("carbs:20", id: id)

        #expect(!result.acknowledged)
        #expect(executions.value == 1)
    }

    @Test("Request IDs are scoped per app") func testScopedPerApp() async {
        let id = UUID()
        _ = await run(id: id)
        _ = await run(id: id, app: UUID())

        #expect(executions.value == 2)
    }

    @Test("A cache full of running requests rejects instead of evicting one") func testFull() async {
        let small = WatchCommandPipeline(
            authorization: authorization,
            cache: WatchCommandRequestCache(capacity: 1),
            now: { [clock] in clock.now }
        )
        let gate = TestGate()
        let pending = Task { await run(on: small, execute: guardedWrite(parkingOn: gate)) }
        await gate.waitForArrivals()

        let rejected = await run(on: small)
        gate.open()

        #expect(rejected.message == "Too many requests in progress. Please try again.")
        #expect(await pending.value.acknowledged)
    }

    @Test("An expired request replays its cached result without re-running") func testExpiredReplay() async {
        let id = UUID()
        let first = await run(id: id, age: WatchCommandPipeline.maximumCommandAge - 5)
        clock.advance(by: 10)

        #expect(await run(id: id, age: WatchCommandPipeline.maximumCommandAge - 5) == first)
        #expect(executions.value == 1)
    }

    // MARK: - Safe Logging

    @Test("Outcomes are logged at info and refusals of misuse at warning") func testLogLevels() async {
        _ = await run()
        let id = UUID()
        _ = await run("carbs:10", id: id)
        _ = await run("carbs:20", id: id)

        #expect(logs.entries.contains { $0.level == .info && $0.line == "Watch carbs command done (success)" })
        #expect(logs.entries.contains { $0.level == .warning && $0.line.contains("request ID was already used") })
    }

    @Test("Error categories are stable and content-free") func testErrorCategories() {
        #expect(WatchCommandErrorCategory.name(for: CoreDataError.fetchError(function: "f", file: "g")) == "coreData")
        #expect(WatchCommandErrorCategory.name(for: CancellationError()) == "cancelled")
        let saveError = NSError(domain: NSCocoaErrorDomain, code: 134_030, userInfo: ["detail": SensitiveTestError.marker])
        #expect(WatchCommandErrorCategory.name(for: saveError) == "cocoa(134030)")
        #expect(WatchCommandErrorCategory.name(for: SensitiveTestError()) == "unexpected")
    }
}

final class ExecutionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    var value: Bool { lock.withLock { isSet } }

    func set() {
        lock.withLock { isSet = true }
    }
}
