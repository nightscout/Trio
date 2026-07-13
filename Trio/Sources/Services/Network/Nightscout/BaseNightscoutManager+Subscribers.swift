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
    /// NSFetchedResultsControllers. Each controller fires when un-uploaded items appear (or drop
    /// out after a successful upload). We rely on the per-pipeline throttle so rapid changes
    /// don't spam Nightscout.
    func wireUploadControllers() {
        determinationUploadControllerDelegate.onContentChange = { [weak self] in
            self?.requestUpload(.deviceStatus)
        }
        overrideUploadControllerDelegate.onContentChange = { [weak self] in
            self?.requestUpload(.overrides)
        }
        overrideRunUploadControllerDelegate.onContentChange = { [weak self] in
            self?.requestUpload(.overrides)
        }
        tempTargetUploadControllerDelegate.onContentChange = { [weak self] in
            self?.requestUpload(.tempTargets)
        }
        tempTargetRunUploadControllerDelegate.onContentChange = { [weak self] in
            self?.requestUpload(.tempTargets)
        }
        pumpEventUploadControllerDelegate.onContentChange = { [weak self] in
            self?.requestUpload(.pumpHistory)
        }
        carbEntryUploadControllerDelegate.onContentChange = { [weak self] in
            self?.requestUpload(.carbs)
        }
        glucoseUploadControllerDelegate.onContentChange = { [weak self] in
            self?.requestUpload(.glucose)
        }

        // performFetch must run on the viewContext's queue (main).
        Task { @MainActor in
            do {
                try self.determinationUploadController.performFetch()
                try self.overrideUploadController.performFetch()
                try self.overrideRunUploadController.performFetch()
                try self.tempTargetUploadController.performFetch()
                try self.tempTargetRunUploadController.performFetch()
                try self.pumpEventUploadController.performFetch()
                try self.carbEntryUploadController.performFetch()
                try self.glucoseUploadController.performFetch()
            } catch {
                debug(.nightscout, "\(DebuggingIdentifiers.failed) Failed to set up Nightscout upload controllers: \(error)")
            }
        }
    }
}
