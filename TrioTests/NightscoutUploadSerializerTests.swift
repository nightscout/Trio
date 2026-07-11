import Foundation
import Testing

@testable import Trio

@Suite("Nightscout Upload Serializer Tests") struct NightscoutUploadSerializerTests {
    /// Records whether an operation is currently in flight and flags any overlap.
    private actor OverlapDetector {
        private var inFlight = false
        private(set) var overlapDetected = false
        private(set) var completedRuns = 0

        func enter() {
            if inFlight { overlapDetected = true }
            inFlight = true
        }

        func exit() {
            inFlight = false
            completedRuns += 1
        }
    }

    /// Ordered log of named events across concurrent tasks, with a run counter.
    private actor EventLog {
        private(set) var events: [String] = []
        private var runNumber = 0

        func append(_ event: String) { events.append(event) }

        func beginRun() -> Int {
            runNumber += 1
            return runNumber
        }
    }

    /// One-shot gate that suspends waiters until opened.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// Polls until `condition` is true, giving up after ~2 seconds so a broken
    /// serializer fails the test instead of hanging it.
    private func waitUntil(_ condition: @escaping @Sendable() async -> Bool) async throws {
        for _ in 0 ..< 400 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test("Concurrent runs of the same pipeline never overlap") func noOverlapWithinPipeline() async {
        let detector = OverlapDetector()
        let serializer = NightscoutUploadSerializer { _ in
            await detector.enter()
            try? await Task.sleep(nanoseconds: 20_000_000)
            await detector.exit()
        }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 10 {
                group.addTask { await serializer.run(.overrides) }
            }
        }

        #expect(await detector.overlapDetected == false, "No two runs of the same pipeline may be in flight at once")
        #expect(await detector.completedRuns >= 1, "At least one run must execute")
    }

    @Test("A run requested mid-flight executes only after the current one finishes") func queuedRunWaitsForCurrent() async throws {
        let log = EventLog()
        let gate = Gate()
        let serializer = NightscoutUploadSerializer { _ in
            let n = await log.beginRun()
            await log.append("start-\(n)")
            if n == 1 { await gate.wait() }
            await log.append("end-\(n)")
        }

        await serializer.request(.overrides)
        try await waitUntil { await log.events.contains("start-1") }

        await serializer.request(.overrides)
        await gate.open()
        try await waitUntil { await log.events.contains("end-2") }

        #expect(await log.events == ["start-1", "end-1", "start-2", "end-2"])
    }

    @Test("Requests made while a run is in flight coalesce into a single follow-up run") func requestsCoalesceIntoOneFollowUp(
    ) async throws {
        let log = EventLog()
        let gate = Gate()
        let serializer = NightscoutUploadSerializer { _ in
            let n = await log.beginRun()
            await log.append("run-\(n)")
            if n == 1 { await gate.wait() }
        }

        await serializer.request(.glucose)
        try await waitUntil { await log.events.contains("run-1") }

        // All five requests arrive while the first run is blocked, so they must
        // coalesce into exactly one follow-up run.
        for _ in 0 ..< 5 {
            await serializer.request(.glucose)
        }

        await gate.open()
        try await waitUntil { await log.events.contains("run-2") }
        // Grace period: any extra (incorrect) follow-up runs would surface here.
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await log.events == ["run-1", "run-2"], "Coalesced requests must produce exactly one follow-up run")
    }

    @Test("run returns only after its own operation has completed") func runAwaitsOwnOperation() async {
        let log = EventLog()
        let serializer = NightscoutUploadSerializer { _ in
            let n = await log.beginRun()
            await log.append("run-\(n)")
        }

        await serializer.run(.carbs)
        #expect(await log.events == ["run-1"])

        await serializer.run(.carbs)
        #expect(await log.events == ["run-1", "run-2"])
    }

    @Test("Different pipelines run independently of each other") func pipelinesAreIndependent() async throws {
        let log = EventLog()
        let gate = Gate()
        let serializer = NightscoutUploadSerializer { pipeline in
            if pipeline == .overrides {
                await log.append("overrides-start")
                await gate.wait()
                await log.append("overrides-end")
            } else {
                await log.append("tempTargets-done")
            }
        }

        await serializer.request(.overrides)
        try await waitUntil { await log.events.contains("overrides-start") }

        // Safety valve: if pipelines were wrongly serialized against each other,
        // the tempTargets run below would be stuck behind the gated overrides run.
        // Opening the gate after a delay lets the test fail on ordering instead of hanging.
        let safetyValve = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await gate.open()
        }

        await serializer.run(.tempTargets)
        await gate.open()
        try await waitUntil { await log.events.contains("overrides-end") }
        safetyValve.cancel()

        #expect(await log.events == ["overrides-start", "tempTargets-done", "overrides-end"])
    }
}
