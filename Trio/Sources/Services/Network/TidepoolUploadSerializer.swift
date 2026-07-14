import Foundation

/// Logical Tidepool upload pipelines, used as the serializer's coalescing keys.
///
/// A pipeline may only coalesce when its operation gathers everything still pending at run
/// time, so a dropped request's data is picked up by the run already waiting to start. The
/// delete pipelines carry a unique payload per request and must never coalesce.
enum TidepoolUploadPipeline: String {
    case carbs
    case carbsDelete = "carbs-delete"
    case dose
    case doseDelete = "dose-delete"
    case glucose
    case settings

    var coalesces: Bool {
        switch self {
        case .carbs,
             .dose,
             .glucose,
             .settings:
            return true
        case .carbsDelete,
             .doseDelete:
            return false
        }
    }
}

/// Runs enqueued upload operations one at a time, in order: each starts only after the previous
/// one has fully completed, including its network round-trip.
///
/// Serialization is global across pipelines because concurrent uploads can each trigger a
/// session refresh that reuses Tidepool's single-use refresh token, invalidating the session.
///
/// Requests for a coalescing pipeline fold together: while a run is enqueued but not yet
/// started, further requests are dropped (the waiting run fetches their data anyway), and a
/// request arriving mid-run chains at most one follow-up, which also serves as a retry after a
/// failed run. A burst of triggers therefore costs at most one waiting run per pipeline.
///
/// A watchdog abandons the chain when the head operation exceeds `watchdogLimit`, e.g. after
/// the app was suspended mid-request and the completion was lost. It uses wall-clock time,
/// which keeps advancing while the process is suspended. Abandoning bumps `generation` so
/// orphaned operations bail out instead of racing the replacement chain.
actor TidepoolUploadSerializer {
    private let watchdogLimit: TimeInterval
    private var tail: Task<Void, Never>?
    private var generation = 0
    /// Pipelines with a run enqueued but not yet started. A coalescing request for one of these
    /// is dropped; the pipeline leaves the set when its run begins, so a request arriving during
    /// execution chains a fresh follow-up.
    private var waiting: Set<TidepoolUploadPipeline> = []
    private var headPipeline: TidepoolUploadPipeline?
    private var headStart: Date?

    init(watchdogLimit: TimeInterval = 10 * 60) {
        self.watchdogLimit = watchdogLimit
    }

    /// True while `generation` identifies the live chain. Operations making more than one
    /// network call re-check this between calls and bail out once their chain is abandoned.
    func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation
    }

    func enqueue(_ pipeline: TidepoolUploadPipeline, _ operation: @escaping (_ generation: Int) async -> Void) {
        recoverIfWedged()
        if pipeline.coalesces {
            guard !waiting.contains(pipeline) else { return }
            waiting.insert(pipeline)
        }
        let generation = generation
        let previous = tail
        // Pin the chain's priority rather than inherit the caller's: .utility stays
        // scheduled during background execution windows (.background would not),
        // without running uploads at UI priority.
        tail = Task(priority: .utility) {
            await previous?.value
            guard await self.begin(pipeline, generation: generation) else { return }
            await operation(generation)
            await self.end(generation: generation)
        }
    }

    /// Abandons the chain if its head operation has exceeded the wall-clock watchdog limit.
    /// Called from paths that keep running while the pipeline itself is wedged.
    func recoverIfWedged() {
        guard let start = headStart else { return }
        let age = Date().timeIntervalSince(start)
        guard age > watchdogLimit else { return }
        warning(
            .service,
            "Tidepool upload chain wedged: '\(headPipeline?.rawValue ?? "?")' has not completed after \(Int(age))s; abandoning chain and starting fresh"
        )
        generation += 1
        tail = nil
        waiting.removeAll()
        headStart = nil
        headPipeline = nil
    }

    private func begin(_ pipeline: TidepoolUploadPipeline, generation: Int) -> Bool {
        guard isCurrent(generation) else { return false }
        waiting.remove(pipeline)
        headPipeline = pipeline
        headStart = Date()
        return true
    }

    private func end(generation: Int) {
        guard isCurrent(generation) else { return }
        headStart = nil
        headPipeline = nil
    }
}

// MARK: - Completion-to-async bridge

/// One-shot resume guard for a continuation raced by a completion handler and a timeout. Only the
/// first `resume(_:)` takes effect.
private final class SingleResumer<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    func attach(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

enum TidepoolUploadError: Error {
    /// The upload's completion handler never fired within the allotted time.
    /// `label` identifies which upload (e.g. "glucose", "dose") so the timeout is diagnosable in logs.
    case timedOut(label: String)
}

extension TidepoolUploadSerializer {
    /// Bridges a completion-based upload into async/await with a timeout, so a call that never calls
    /// back resolves to a `.timedOut` failure instead of wedging the serializer indefinitely.
    static func awaitUpload(
        _ label: String,
        timeout: TimeInterval = 120,
        _ operation: (@escaping (Result<Bool, Error>) -> Void) -> Void
    ) async -> Result<Bool, Error> {
        let resumer = SingleResumer<Result<Bool, Error>>()
        return await withCheckedContinuation { continuation in
            resumer.attach(continuation)

            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return // cancelled: completion already fired
                }
                resumer.resume(.failure(TidepoolUploadError.timedOut(label: label)))
            }

            operation { result in
                timeoutTask.cancel()
                resumer.resume(result)
            }
        }
    }
}
