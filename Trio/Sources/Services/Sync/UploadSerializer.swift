import Foundation

/// Task-local storage for `UploadSerializer`. Lives outside the actor because
/// `@TaskLocal` requires a static stored property, which generic types cannot declare.
private enum UploadSerializerTaskLocals {
    /// Identifies the (serializer instance, pipeline) pair whose upload operation
    /// the current task is executing, if any.
    ///
    /// `AnyHashable` erases the serializer's concrete pipeline type; the values it
    /// wraps are plain pipeline enum cases, so sending them across tasks is safe.
    struct ActiveRun: Equatable, @unchecked Sendable {
        let serializer: ObjectIdentifier
        let pipeline: AnyHashable
    }

    @TaskLocal static var activeRun: ActiveRun?
}

/// Coalesces and serializes upload runs per pipeline.
///
/// Runs of the same pipeline never overlap: concurrent runs would each fetch the
/// rows still marked "not yet uploaded" and POST them twice, and a backend may
/// store concurrent identical POSTs as duplicates. A follow-up run re-fetches only
/// after the previous run has marked its rows uploaded, so nothing is sent twice.
///
/// An idle pipeline starts a run immediately; while a run is in flight, exactly one
/// follow-up is queued and further requests coalesce into it. No request is dropped.
/// Every run executes the upload operation provided at init.
///
/// A `run(_:)` issued from inside its own pipeline's upload operation would deadlock
/// awaiting itself; the serializer asserts in debug builds and downgrades the call to
/// a fire-and-forget request in release.
///
/// Backend-agnostic: each uploader (Nightscout, Nocturne, …) owns its own instance,
/// parameterized by its own pipeline type. The reentrancy guard distinguishes
/// serializer instances, so one serializer's upload operation may freely await a
/// different serializer's `run(_:)` for an equal pipeline value.
actor UploadSerializer<Pipeline: Hashable & Sendable> {
    /// Uploads everything still pending for a pipeline.
    private let uploadOperation: @Sendable(Pipeline) async -> Void

    /// Called when `run(_:)` is invoked from inside the same pipeline's upload
    /// operation. Asserts by default; tests inject a recorder.
    private let onReentrantRun: @Sendable(Pipeline) -> Void

    /// Run currently in flight per pipeline.
    private var current: [Pipeline: Task<Void, Never>] = [:]
    /// Follow-up run queued behind the current one, at most one per pipeline.
    private var queued: [Pipeline: Task<Void, Never>] = [:]

    init(
        uploadOperation: @escaping @Sendable(Pipeline) async -> Void,
        onReentrantRun: @escaping @Sendable(Pipeline) -> Void = { pipeline in
            assertionFailure("run(.\(pipeline)) called from inside its own upload operation")
        }
    ) {
        self.uploadOperation = uploadOperation
        self.onReentrantRun = onReentrantRun
    }

    /// Fire-and-forget request. Coalesces into an already queued follow-up if present.
    /// Safe to call from inside an upload operation.
    func request(_ pipeline: Pipeline) {
        _ = scheduleRun(pipeline)
    }

    /// Awaitable request: returns once the run serving it has completed. For callers
    /// that must know the upload attempt has finished before proceeding.
    func run(_ pipeline: Pipeline) async {
        guard UploadSerializerTaskLocals.activeRun != activeRun(for: pipeline) else {
            onReentrantRun(pipeline)
            request(pipeline)
            return
        }
        await scheduleRun(pipeline).value
    }

    private func activeRun(for pipeline: Pipeline) -> UploadSerializerTaskLocals.ActiveRun {
        UploadSerializerTaskLocals.ActiveRun(serializer: ObjectIdentifier(self), pipeline: AnyHashable(pipeline))
    }

    /// Returns the run that serves a request made now: the queued follow-up if one
    /// exists, a new follow-up chained behind the current run, or a fresh run.
    private func scheduleRun(_ pipeline: Pipeline) -> Task<Void, Never> {
        if let followUp = queued[pipeline] {
            return followUp
        }
        let activeRun = activeRun(for: pipeline)
        if let running = current[pipeline] {
            let followUp = Task { [running, uploadOperation, weak self] in
                await running.value
                await self?.promoteQueuedRun(pipeline)
                await UploadSerializerTaskLocals.$activeRun.withValue(activeRun) {
                    await uploadOperation(pipeline)
                }
                await self?.finishCurrentRun(pipeline)
            }
            queued[pipeline] = followUp
            return followUp
        }
        let run = Task { [uploadOperation, weak self] in
            await UploadSerializerTaskLocals.$activeRun.withValue(activeRun) {
                await uploadOperation(pipeline)
            }
            await self?.finishCurrentRun(pipeline)
        }
        current[pipeline] = run
        return run
    }

    private func promoteQueuedRun(_ pipeline: Pipeline) {
        current[pipeline] = queued[pipeline]
        queued[pipeline] = nil
    }

    private func finishCurrentRun(_ pipeline: Pipeline) {
        current[pipeline] = nil
    }
}
