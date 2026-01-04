import Combine
import CoreData
import Foundation

extension BaseNightscoutManager {
    /// Call once from init. Hooks up:
    /// 1) external upload requests (NotificationCenter)
    /// 2) Core Data change triggers → requests per upload pipeline
    /// 3) Glucose storage updates → request glucose pipeline
    func wireSubscribers() {
        wireExternalUploadRequests()
        wireCoreDataSubscribers()
        wireGlucoseStorageSubscriber()
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

    /// Maps Core Data entity changes into upload pipeline requests. We rely on
    /// per-pipeline throttle so rapid changes don’t spam Nightscout.
    func wireCoreDataSubscribers() {
        coreDataPublisher?
            .filteredByEntityName("OrefDetermination")
            .sink { [weak self] _ in self?.requestUpload(.deviceStatus) }
            .store(in: &subscriptions)

        coreDataPublisher?
            .filteredByEntityName("OverrideStored")
            .sink { [weak self] _ in self?.requestUpload(.overrides) }
            .store(in: &subscriptions)

        coreDataPublisher?
            .filteredByEntityName("OverrideRunStored")
            .sink { [weak self] _ in self?.requestUpload(.overrides) }
            .store(in: &subscriptions)

        coreDataPublisher?
            .filteredByEntityName("TempTargetStored")
            .sink { [weak self] _ in self?.requestUpload(.tempTargets) }
            .store(in: &subscriptions)

        coreDataPublisher?
            .filteredByEntityName("TempTargetRunStored")
            .sink { [weak self] _ in self?.requestUpload(.tempTargets) }
            .store(in: &subscriptions)

        coreDataPublisher?
            .filteredByEntityName("PumpEventStored")
            .sink { [weak self] _ in self?.requestUpload(.pumpHistory) }
            .store(in: &subscriptions)

        coreDataPublisher?
            .filteredByEntityName("CarbEntryStored")
            .sink { [weak self] _ in self?.requestUpload(.carbs) }
            .store(in: &subscriptions)

        coreDataPublisher?
            .filteredByEntityName("GlucoseStored")
            .sink { [weak self] _ in
                self?.requestUpload(.glucose)
                self?.requestUpload(.manualGlucose)
            }
            .store(in: &subscriptions)
    }

    /// Glucose storage updates → request glucose pipeline
    func wireGlucoseStorageSubscriber() {
        glucoseStorage.updatePublisher
            .receive(on: queue)
            .sink { [weak self] _ in
                self?.requestUpload(.glucose)
            }
            .store(in: &subscriptions)
    }
}
