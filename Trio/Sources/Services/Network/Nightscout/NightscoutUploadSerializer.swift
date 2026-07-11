import Foundation

/// Coalesces and serializes Nightscout upload runs per pipeline.
///
/// Runs of the same pipeline never overlap: concurrent runs would each fetch the
/// rows still marked `isUploadedToNS == false` and POST them twice, and Nightscout
/// stores concurrent identical POSTs as duplicates. A follow-up run re-fetches only
/// after the previous run has marked its rows uploaded, so nothing is sent twice.
///
/// An idle pipeline starts a run immediately; while a run is in flight, exactly one
/// follow-up is queued and further requests coalesce into it. No request is dropped.
/// Every run executes the upload operation provided at init.
actor NightscoutUploadSerializer {
    /// Uploads everything still pending for a pipeline.
    private let uploadOperation: @Sendable(NightscoutUploadPipeline) async -> Void

    /// Run currently in flight per pipeline.
    private var current: [NightscoutUploadPipeline: Task<Void, Never>] = [:]
    /// Follow-up run queued behind the current one, at most one per pipeline.
    private var queued: [NightscoutUploadPipeline: Task<Void, Never>] = [:]

    init(uploadOperation: @escaping @Sendable(NightscoutUploadPipeline) async -> Void) {
        self.uploadOperation = uploadOperation
    }

    /// Fire-and-forget request. Coalesces into an already queued follow-up if present.
    func request(_ pipeline: NightscoutUploadPipeline) {
        _ = scheduleRun(pipeline)
    }

    /// Awaitable request: returns once the run serving it has completed. For callers
    /// that must know the upload attempt has finished before proceeding.
    func run(_ pipeline: NightscoutUploadPipeline) async {
        await scheduleRun(pipeline).value
    }

    /// Returns the run that serves a request made now: the queued follow-up if one
    /// exists, a new follow-up chained behind the current run, or a fresh run.
    private func scheduleRun(_ pipeline: NightscoutUploadPipeline) -> Task<Void, Never> {
        if let followUp = queued[pipeline] {
            return followUp
        }
        if let running = current[pipeline] {
            let followUp = Task { [running, uploadOperation, weak self] in
                await running.value
                await self?.promoteQueuedRun(pipeline)
                await uploadOperation(pipeline)
                await self?.finishCurrentRun(pipeline)
            }
            queued[pipeline] = followUp
            return followUp
        }
        let run = Task { [uploadOperation, weak self] in
            await uploadOperation(pipeline)
            await self?.finishCurrentRun(pipeline)
        }
        current[pipeline] = run
        return run
    }

    private func promoteQueuedRun(_ pipeline: NightscoutUploadPipeline) {
        current[pipeline] = queued[pipeline]
        queued[pipeline] = nil
    }

    private func finishCurrentRun(_ pipeline: NightscoutUploadPipeline) {
        current[pipeline] = nil
    }
}
