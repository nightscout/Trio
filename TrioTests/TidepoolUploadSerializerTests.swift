import Foundation
import Testing

@testable import Trio

// MARK: - Upload serialization tests

/// Tracks the start order and peak concurrency of serialized operations.
private actor Recorder {
    private(set) var order: [Int] = []
    private var active = 0
    private(set) var maxActive = 0

    func begin(_ index: Int) {
        order.append(index)
        active += 1
        maxActive = max(maxActive, active)
    }

    func end() {
        active -= 1
    }
}

/// Counts completed runs, optionally keyed by pipeline.
private actor Counter {
    private(set) var counts: [TidepoolUploadPipeline: Int] = [:]

    func increment(_ pipeline: TidepoolUploadPipeline) {
        counts[pipeline, default: 0] += 1
    }

    var total: Int {
        counts.values.reduce(0, +)
    }
}

/// One-shot async gate: `wait()` suspends until `open()`; opening before anyone waits is remembered.
private actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

@Suite("Tidepool upload serialization") struct TidepoolUploadSerializerTests {
    /// Enqueue a sentinel on a non-coalescing pipeline and await it; the chain guarantees it
    /// runs only after all previously enqueued work has completed.
    private func drain(_ serializer: TidepoolUploadSerializer) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { await serializer.enqueue(.doseDelete) { _ in continuation.resume() } }
        }
    }

    /// Operations must run one at a time, in enqueue order. If two ever overlapped, `maxActive`
    /// would exceed 1; if the chain reordered, `order` wouldn't be 0..<count. Uses a delete
    /// pipeline because those never coalesce, so every enqueue produces a run.
    @Test("Serializer runs operations one at a time, in order") func serializesInOrder() async {
        let serializer = TidepoolUploadSerializer()
        let recorder = Recorder()
        let count = 10

        for index in 0 ..< count {
            await serializer.enqueue(.carbsDelete) { _ in
                await recorder.begin(index)
                // Yield instead of sleeping: a real-time sleep makes the stress depend on machine
                // speed (and can mask a race on a fast box). `Task.yield()` deterministically hands
                // the scheduler a chance to run any (incorrectly) concurrent operation, so a broken
                // serializer would push `maxActive` above 1 here without any wall-clock dependence.
                await Task.yield()
                await recorder.end()
            }
        }

        await drain(serializer)

        #expect(await recorder.order == Array(0 ..< count))
        #expect(await recorder.maxActive == 1)
    }

    /// While a run for a coalescing pipeline is in flight, the first new request chains exactly
    /// one follow-up and every further request folds into it. The follow-up re-fetches at run
    /// time, so the dropped requests lose nothing.
    @Test("A burst of requests coalesces into one follow-up run") func coalescesBurstIntoOneFollowUp() async {
        let serializer = TidepoolUploadSerializer()
        let counter = Counter()
        let headStarted = Gate()
        let release = Gate()

        // Head run blocks: simulates an upload with its network round-trip in flight.
        await serializer.enqueue(.glucose) { _ in
            await headStarted.open()
            await release.wait()
            await counter.increment(.glucose)
        }
        await headStarted.wait()

        // Burst while the head is executing: exactly one follow-up may be chained.
        for _ in 0 ..< 5 {
            await serializer.enqueue(.glucose) { _ in await counter.increment(.glucose) }
        }

        await release.open()
        await drain(serializer)

        #expect(await counter.counts[.glucose] == 2) // the head plus one follow-up
    }

    /// Delete pipelines carry a unique payload per request; coalescing would silently drop
    /// deletions, so every enqueue must produce its own run.
    @Test("Delete pipelines never coalesce") func deletePipelinesDoNotCoalesce() async {
        let serializer = TidepoolUploadSerializer()
        let counter = Counter()
        let headStarted = Gate()
        let release = Gate()

        await serializer.enqueue(.carbsDelete) { _ in
            await headStarted.open()
            await release.wait()
            await counter.increment(.carbsDelete)
        }
        await headStarted.wait()

        for _ in 0 ..< 3 {
            await serializer.enqueue(.carbsDelete) { _ in await counter.increment(.carbsDelete) }
        }

        await release.open()
        await drain(serializer)

        #expect(await counter.counts[.carbsDelete] == 4)
    }

    /// Coalescing is keyed per pipeline: a waiting glucose follow-up must not absorb a carbs
    /// request, and vice versa.
    @Test("Coalescing is independent per pipeline") func coalescingIsPerPipeline() async {
        let serializer = TidepoolUploadSerializer()
        let counter = Counter()
        let headStarted = Gate()
        let release = Gate()

        await serializer.enqueue(.glucose) { _ in
            await headStarted.open()
            await release.wait()
            await counter.increment(.glucose)
        }
        await headStarted.wait()

        // Two requests per pipeline while the head is executing: one follow-up each.
        for _ in 0 ..< 2 {
            await serializer.enqueue(.glucose) { _ in await counter.increment(.glucose) }
            await serializer.enqueue(.carbs) { _ in await counter.increment(.carbs) }
        }

        await release.open()
        await drain(serializer)

        #expect(await counter.counts[.glucose] == 2) // the head plus one follow-up
        #expect(await counter.counts[.carbs] == 1) // one follow-up, second request coalesced
    }

    @Test("Watchdog abandons a wedged chain so later uploads run again") func watchdogRecoversWedgedChain() async {
        let serializer = TidepoolUploadSerializer(watchdogLimit: 0.2)
        let started = Gate()

        // Head op wedges forever — simulates a completion lost while the app was suspended.
        await serializer.enqueue(.glucose) { _ in
            await started.open()
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }

        // Only start the clock once the op is definitely running, then exceed the limit.
        await started.wait()
        try? await Task.sleep(nanoseconds: 300_000_000)

        // The next enqueue trips the watchdog; the new op must run on a fresh chain instead of
        // queueing forever behind the wedged one.
        let ran = await withCheckedContinuation { continuation in
            Task {
                await serializer.enqueue(.carbs) { _ in continuation.resume(returning: true) }
            }
        }
        #expect(ran)
    }

    /// A request coalesced into a follow-up that is stuck behind a wedged head must not stay
    /// dropped after the watchdog abandons the chain: abandoning clears the coalescing state,
    /// so the pipeline can enqueue a live run on the fresh chain.
    @Test("Watchdog clears coalescing state for the fresh chain") func watchdogClearsCoalescingState() async {
        let serializer = TidepoolUploadSerializer(watchdogLimit: 0.2)
        let started = Gate()

        await serializer.enqueue(.glucose) { _ in
            await started.open()
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }
        await started.wait()

        // Chained behind the wedged head; never runs. Without clearing, `.glucose` would stay
        // marked as waiting and the post-recovery request below would be coalesced into it.
        await serializer.enqueue(.glucose) { _ in }

        try? await Task.sleep(nanoseconds: 300_000_000)
        await serializer.recoverIfWedged()

        let ran = await withCheckedContinuation { continuation in
            Task {
                await serializer.enqueue(.glucose) { _ in continuation.resume(returning: true) }
            }
        }
        #expect(ran)
    }

    @Test("An abandoned operation sees a stale generation and bails out") func abandonedOperationSeesStaleGeneration() async {
        let serializer = TidepoolUploadSerializer(watchdogLimit: 0.2)
        let started = Gate()
        let release = Gate()

        async let observed: Bool = withCheckedContinuation { continuation in
            Task {
                await serializer.enqueue(.glucose) { generation in
                    await started.open()
                    await release.wait() // held wedged past the watchdog limit
                    await continuation.resume(returning: serializer.isCurrent(generation))
                }
            }
        }

        await started.wait()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await serializer.recoverIfWedged() // watchdog abandons the chain

        // The resumed orphan must read its generation as stale.
        await release.open()
        #expect(await observed == false)
    }

    /// An orphaned operation resuming after the watchdog abandoned its chain must not disturb
    /// the fresh chain's bookkeeping: if its late `end` cleared the new head's start time, the
    /// watchdog would be blind to a wedged new head.
    @Test("An orphan's late completion leaves the fresh chain's watchdog intact") func orphanCompletionLeavesFreshChainIntact() async {
        let serializer = TidepoolUploadSerializer(watchdogLimit: 0.2)
        let orphanStarted = Gate()
        let orphanRelease = Gate()
        let orphanDone = Gate()
        let freshStarted = Gate()

        // Head op wedges past the limit and gets abandoned, becoming an orphan.
        await serializer.enqueue(.glucose) { _ in
            await orphanStarted.open()
            await orphanRelease.wait()
            await orphanDone.open()
        }
        await orphanStarted.wait()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await serializer.recoverIfWedged()

        // A new head starts on the fresh chain and wedges in turn.
        await serializer.enqueue(.glucose) { _ in
            await freshStarted.open()
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }
        await freshStarted.wait()

        // The orphan now resumes and finishes; its late `end` must not clear the fresh
        // head's start time.
        await orphanRelease.open()
        await orphanDone.wait()

        // The fresh head exceeds the limit; the watchdog must still see it and recover.
        try? await Task.sleep(nanoseconds: 300_000_000)
        await serializer.recoverIfWedged()

        let ran = await withCheckedContinuation { continuation in
            Task {
                await serializer.enqueue(.glucose) { _ in continuation.resume(returning: true) }
            }
        }
        #expect(ran)
    }

    @Test("Watchdog leaves an idle chain alone") func watchdogIgnoresIdleChain() async {
        let serializer = TidepoolUploadSerializer(watchdogLimit: 0.1)

        let firstGeneration = await withCheckedContinuation { continuation in
            Task { await serializer.enqueue(.glucose) { continuation.resume(returning: $0) } }
        }

        // Well past the limit, but with no operation running the watchdog must not trip.
        try? await Task.sleep(nanoseconds: 300_000_000)
        await serializer.recoverIfWedged()

        let secondGeneration = await withCheckedContinuation { continuation in
            Task { await serializer.enqueue(.glucose) { continuation.resume(returning: $0) } }
        }
        #expect(firstGeneration == secondGeneration)
    }

    @Test("awaitUpload returns the completion's result") func awaitUploadReturnsResult() async {
        let result = await TidepoolUploadSerializer.awaitUpload("test", timeout: 5) { completion in
            completion(.success(true))
        }

        guard case .success(true) = result else {
            Issue.record("expected .success(true), got \(result)")
            return
        }
    }

    @Test("awaitUpload times out when the completion never fires") func awaitUploadTimesOut() async {
        let result = await TidepoolUploadSerializer.awaitUpload("test", timeout: 0.2) { _ in
            // Never call the completion: simulates a wedged network/auth call.
        }

        guard case let .failure(error) = result,
              let uploadError = error as? TidepoolUploadError,
              case .timedOut = uploadError
        else {
            Issue.record("expected .timedOut failure, got \(result)")
            return
        }
    }

    @Test("A late completion after timeout is ignored, not a crash") func lateCompletionIsIgnored() async {
        var storedCompletion: ((Result<Bool, Error>) -> Void)?

        let result = await TidepoolUploadSerializer.awaitUpload("test", timeout: 0.2) { completion in
            storedCompletion = completion // fire it after the timeout below
        }

        guard case .failure = result else {
            Issue.record("expected timeout failure, got \(result)")
            return
        }

        // Resolving the captured completion after the one-shot guard already resumed must be a no-op.
        storedCompletion?(.success(true))
    }
}
