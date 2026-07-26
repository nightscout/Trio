import Combine
import CoreData
import Foundation

extension BaseNightscoutManager {
    /// Call once from init. Hooks up:
    /// 1) external upload requests (NotificationCenter)
    /// 2) Core Data "not yet uploaded" triggers → requests per upload pipeline
    func wireSubscribers() {
        wireExternalUploadRequests()
        wireUploadControllers()
    }

    /// Listens for `.nightscoutUploadRequested`, converts userInfo pipelines to enums,
    /// and requests those upload pipelines. Posts `.nightscoutUploadDidFinish` after enqueuing.
    func wireExternalUploadRequests() {
        Foundation.NotificationCenter.default.publisher(for: .nightscoutUploadRequested)
            .sink { [weak self] note in
                guard let self else { return }
                let pipelines = (note.userInfo?[NightscoutNotificationKey.uploadPipelines] as? [String])?
                    .compactMap(NightscoutUploadPipeline.init(rawValue:)) ?? []

                for pipeline in pipelines { self.requestUpload(pipeline) }

                var info: [AnyHashable: Any] = [NightscoutNotificationKey.uploadPipelines: pipelines.map(\.rawValue)]
                if let src = note.userInfo?[NightscoutNotificationKey.source] { info[NightscoutNotificationKey.source] = src }
                Foundation.NotificationCenter.default.post(name: .nightscoutUploadDidFinish, object: nil, userInfo: info)
            }
            .store(in: &subscriptions)
    }

    /// Maps Core Data "not yet uploaded to Nightscout" sets to upload pipeline requests via
    /// `UploadTriggerController`s. Each trigger fires when un-uploaded items appear (or drop
    /// out after a successful upload). Requests are coalesced and serialized per pipeline so
    /// rapid changes don't spam Nightscout.
    func wireUploadControllers() {
        func notYetUploadedToNS(_ dateKey: String) -> NSPredicate {
            NSPredicate(
                format: "%K >= %@ AND isUploadedToNS == %@",
                dateKey,
                Date.oneDayAgo as NSDate,
                false as NSNumber
            )
        }

        // Overrides and temp targets each have two triggers (Stored + RunStored) feeding
        // one pipeline; determinations feed the deviceStatus pipeline.
        let triggers: [(entityName: String, sortKey: String, predicate: NSPredicate, batchSize: Int?,
                        pipeline: NightscoutUploadPipeline)] = [
            ("OrefDetermination", "deliverAt", notYetUploadedToNS("deliverAt"), 50, .deviceStatus),
            ("OverrideStored", "date", notYetUploadedToNS("date"), nil, .overrides),
            ("OverrideRunStored", "startDate", notYetUploadedToNS("startDate"), nil, .overrides),
            ("TempTargetStored", "date", notYetUploadedToNS("date"), nil, .tempTargets),
            ("TempTargetRunStored", "startDate", notYetUploadedToNS("startDate"), nil, .tempTargets),
            ("PumpEventStored", "timestamp", NSPredicate.pumpEventsNotYetUploadedToNightscout, 50, .pumpHistory),
            ("CarbEntryStored", "date", notYetUploadedToNS("date"), 50, .carbs),
            ("GlucoseStored", "date", NSPredicate.glucoseNotYetUploadedToNightscout, 50, .glucose)
        ]

        uploadTriggers = triggers.map { trigger in
            UploadTriggerController(
                entityName: trigger.entityName,
                sortKey: trigger.sortKey,
                predicate: trigger.predicate,
                fetchBatchSize: trigger.batchSize,
                context: viewContext
            ) { [weak self] in
                self?.requestUpload(trigger.pipeline)
            }
        }

        // performFetch must run on the viewContext's queue (main).
        Task { @MainActor in
            do {
                for trigger in self.uploadTriggers {
                    try trigger.start()
                }
            } catch {
                debug(.nightscout, "\(DebuggingIdentifiers.failed) Failed to set up Nightscout upload controllers: \(error)")
            }
        }
    }
}
