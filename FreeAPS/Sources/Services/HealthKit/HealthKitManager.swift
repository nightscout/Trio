import Combine
import CoreData
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import Swinject

protocol HealthKitManager: GlucoseSource {
    /// Check all needed permissions
    /// Return false if one or more permissions are deny or not choosen
    var areAllowAllPermissions: Bool { get }
    /// Check availability to save data of BG type to Health store
    func checkAvailabilitySaveBG() -> Bool
    /// Requests user to give permissions on using HealthKit
    func requestPermission() async throws -> Bool
    /// Save blood glucose to Health store
    func uploadGlucose() async
    /// Save carbs to Health store
    func uploadCarbs() async
    /// Save Insulin to Health store
    func uploadInsulin() async
    /// Create observer for data passing beetwen Health Store and Trio
    func createBGObserver()
    /// Enable background delivering objects from Apple Health to Trio
    func enableBackgroundDelivery()
    /// Delete glucose with syncID
    func deleteGlucose(syncID: String) async
    /// delete carbs with syncID
    func deleteMealData(byID id: String, sampleType: HKSampleType) async
    /// delete insulin with syncID
    func deleteInsulin(syncID: String)
}

public enum AppleHealthConfig {
    // unwraped HKObjects
    static var readPermissions: Set<HKSampleType> {
        Set([healthBGObject].compactMap { $0 }) }

    static var writePermissions: Set<HKSampleType> {
        Set([healthBGObject, healthCarbObject, healthFatObject, healthProteinObject, healthInsulinObject].compactMap { $0 }) }

    // link to object in HealthKit
    static let healthBGObject = HKObjectType.quantityType(forIdentifier: .bloodGlucose)
    static let healthCarbObject = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
    static let healthFatObject = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)
    static let healthProteinObject = HKObjectType.quantityType(forIdentifier: .dietaryProtein)
    static let healthInsulinObject = HKObjectType.quantityType(forIdentifier: .insulinDelivery)

    // Meta-data key of FreeASPX data in HealthStore
    static let freeAPSMetaKey = "From Trio"
}

final class BaseHealthKitManager: HealthKitManager, Injectable, CarbsStoredDelegate, PumpHistoryDelegate {
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var healthKitStore: HKHealthStore!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() var carbsStorage: CarbsStorage!
    @Injected() var pumpHistoryStorage: PumpHistoryStorage!

    private var backgroundContext = CoreDataStack.shared.newTaskContext()

    func carbsStorageHasUpdatedCarbs(_: BaseCarbsStorage) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.uploadCarbs()
        }
    }

    func pumpHistoryHasUpdated(_: BasePumpHistoryStorage) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.uploadInsulin()
        }
    }

    private let processQueue = DispatchQueue(label: "BaseHealthKitManager.processQueue")
    private var lifetime = Lifetime()

    // BG that will be return Publisher
    @SyncAccess @Persisted(key: "BaseHealthKitManager.newGlucose") private var newGlucose: [BloodGlucose] = []

    // last anchor for HKAnchoredQuery
    private var lastBloodGlucoseQueryAnchor: HKQueryAnchor? {
        set {
            persistedBGAnchor = try? NSKeyedArchiver.archivedData(withRootObject: newValue as Any, requiringSecureCoding: false)
        }
        get {
            guard let data = persistedBGAnchor else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
    }

    @Persisted(key: "HealthKitManagerAnchor") private var persistedBGAnchor: Data? = nil

    var isAvailableOnCurrentDevice: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var areAllowAllPermissions: Bool {
        Set(AppleHealthConfig.readPermissions.map { healthKitStore.authorizationStatus(for: $0) })
            .intersection([.notDetermined])
            .isEmpty &&
            Set(AppleHealthConfig.writePermissions.map { healthKitStore.authorizationStatus(for: $0) })
            .intersection([.sharingDenied, .notDetermined])
            .isEmpty
    }

    // NSPredicate, which use during load increment BG from Health store
    private var loadBGPredicate: NSPredicate {
        // loading only daily bg
        let predicateByStartDate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-1.days.timeInterval),
            end: nil,
            options: .strictStartDate
        )

        // loading only not FreeAPS bg
        // this predicate dont influence on Deleted Objects, only on added
        let predicateByMeta = HKQuery.predicateForObjects(
            withMetadataKey: AppleHealthConfig.freeAPSMetaKey,
            operatorType: .notEqualTo,
            value: 1
        )

        return NSCompoundPredicate(andPredicateWithSubpredicates: [predicateByStartDate, predicateByMeta])
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        guard isAvailableOnCurrentDevice,
              AppleHealthConfig.healthBGObject != nil else { return }

        carbsStorage.delegate = self
        pumpHistoryStorage.delegate = self

        debug(.service, "HealthKitManager did create")
    }

    func checkAvailabilitySave(objectTypeToHealthStore: HKObjectType) -> Bool {
        healthKitStore.authorizationStatus(for: objectTypeToHealthStore) == .sharingAuthorized
    }

    func checkAvailabilitySaveBG() -> Bool {
        AppleHealthConfig.healthBGObject.map { checkAvailabilitySave(objectTypeToHealthStore: $0) } ?? false
    }

    func requestPermission() async throws -> Bool {
        guard isAvailableOnCurrentDevice else {
            throw HKError.notAvailableOnCurrentDevice
        }
        guard AppleHealthConfig.readPermissions.isNotEmpty, AppleHealthConfig.writePermissions.isNotEmpty else {
            throw HKError.dataNotAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            healthKitStore.requestAuthorization(
                toShare: AppleHealthConfig.writePermissions,
                read: AppleHealthConfig.readPermissions
            ) { status, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    // Glucose Upload

    func uploadGlucose() async {
        await uploadGlucose(glucoseStorage.getGlucoseNotYetUploadedToHealth())
        await uploadGlucose(glucoseStorage.getManualGlucoseNotYetUploadedToHealth())
    }

    func uploadGlucose(_ glucose: [BloodGlucose]) async {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthBGObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType),
              glucose.isNotEmpty
        else { return }

        do {
            // Create HealthKit samples from all the passed glucose values
            let glucoseSamples = glucose.compactMap { glucoseSample -> HKQuantitySample? in
                guard let glucoseValue = glucoseSample.glucose else { return nil }

                return HKQuantitySample(
                    type: sampleType,
                    quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucoseValue)),
                    start: glucoseSample.dateString,
                    end: glucoseSample.dateString,
                    metadata: [
                        HKMetadataKeyExternalUUID: glucoseSample.id,
                        HKMetadataKeySyncIdentifier: glucoseSample.id,
                        HKMetadataKeySyncVersion: 1,
                        AppleHealthConfig.freeAPSMetaKey: true
                    ]
                )
            }

            guard glucoseSamples.isNotEmpty else {
                debug(.service, "No glucose samples available for upload.")
                return
            }

            // Attempt to save the blood glucose samples to Apple Health
            try await healthKitStore.save(glucoseSamples)
            debug(.service, "Successfully stored \(glucoseSamples.count) blood glucose samples in HealthKit.")

            // After successful upload, update the isUploadedToHealth flag in Core Data
            await updateGlucoseAsUploaded(glucose)

        } catch {
            debug(.service, "Failed to upload glucose samples to HealthKit: \(error.localizedDescription)")
        }
    }

    private func updateGlucoseAsUploaded(_ glucose: [BloodGlucose]) async {
        await backgroundContext.perform {
            let ids = glucose.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToHealth = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToHealth: \(error.userInfo)"
                )
            }
        }
    }

    // Carbs Upload

    func uploadCarbs() async {
        await uploadCarbs(carbsStorage.getCarbsNotYetUploadedToHealth())
    }

    func uploadCarbs(_ carbs: [CarbsEntry]) async {
        guard settingsManager.settings.useAppleHealth,
              let carbSampleType = AppleHealthConfig.healthCarbObject,
              let fatSampleType = AppleHealthConfig.healthFatObject,
              let proteinSampleType = AppleHealthConfig.healthProteinObject,
              checkAvailabilitySave(objectTypeToHealthStore: carbSampleType),
              carbs.isNotEmpty
        else { return }

        do {
            var samples: [HKQuantitySample] = []

            // Create HealthKit samples for carbs, fat, and protein
            for allSamples in carbs {
                guard let id = allSamples.id else { continue }

                let startDate = allSamples.actualDate ?? Date()

                // Carbs Sample
                let carbValue = allSamples.carbs
                let carbSample = HKQuantitySample(
                    type: carbSampleType,
                    quantity: HKQuantity(unit: .gram(), doubleValue: Double(carbValue)),
                    start: startDate,
                    end: startDate,
                    metadata: [
                        HKMetadataKeyExternalUUID: id,
                        HKMetadataKeySyncIdentifier: id,
                        HKMetadataKeySyncVersion: 1,
                        AppleHealthConfig.freeAPSMetaKey: true
                    ]
                )
                samples.append(carbSample)

                // Fat Sample (if available)
                if let fatValue = allSamples.fat {
                    let fatSample = HKQuantitySample(
                        type: fatSampleType,
                        quantity: HKQuantity(unit: .gram(), doubleValue: Double(fatValue)),
                        start: startDate,
                        end: startDate,
                        metadata: [
                            HKMetadataKeyExternalUUID: id,
                            HKMetadataKeySyncIdentifier: id,
                            HKMetadataKeySyncVersion: 1,
                            AppleHealthConfig.freeAPSMetaKey: true
                        ]
                    )
                    samples.append(fatSample)
                }

                // Protein Sample (if available)
                if let proteinValue = allSamples.protein {
                    let proteinSample = HKQuantitySample(
                        type: proteinSampleType,
                        quantity: HKQuantity(unit: .gram(), doubleValue: Double(proteinValue)),
                        start: startDate,
                        end: startDate,
                        metadata: [
                            HKMetadataKeyExternalUUID: id,
                            HKMetadataKeySyncIdentifier: id,
                            HKMetadataKeySyncVersion: 1,
                            AppleHealthConfig.freeAPSMetaKey: true
                        ]
                    )
                    samples.append(proteinSample)
                }
            }

            // Attempt to save the samples to Apple Health
            guard samples.isNotEmpty else {
                debug(.service, "No samples available for upload.")
                return
            }

            try await healthKitStore.save(samples)
            debug(.service, "Successfully stored \(samples.count) carb samples in HealthKit.")

            // After successful upload, update the isUploadedToHealth flag in Core Data
            await updateCarbsAsUploaded(carbs)

        } catch {
            debug(.service, "Failed to upload carb samples to HealthKit: \(error.localizedDescription)")
        }
    }

    private func updateCarbsAsUploaded(_ carbs: [CarbsEntry]) async {
        await backgroundContext.perform {
            let ids = carbs.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToHealth = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToHealth: \(error.userInfo)"
                )
            }
        }
    }

    // Insulin Upload

    func uploadInsulin() async {
        await uploadInsulin(pumpHistoryStorage.getPumpHistoryNotYetUploadedToHealth())
    }

    func uploadInsulin(_ insulin: [PumpHistoryEvent]) async {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthInsulinObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType),
              insulin.isNotEmpty
        else { return }

        do {
            let insulinSamples = insulin.compactMap { insulinSample -> HKQuantitySample? in
                guard let insulinValue = insulinSample.amount else { return nil }

                // Determine the insulin delivery reason (bolus or basal)
                let deliveryReason: HKInsulinDeliveryReason
                switch insulinSample.type {
                case .bolus:
                    deliveryReason = .bolus
                case .tempBasal:
                    deliveryReason = .basal
                default:
                    // Skip other types
                    /// If deliveryReason is nil, the compactMap will filter this sample out preventing a crash
                    return nil
                }

                return HKQuantitySample(
                    type: sampleType,
                    quantity: HKQuantity(unit: .internationalUnit(), doubleValue: Double(insulinValue)),
                    start: insulinSample.timestamp,
                    end: insulinSample.timestamp,
                    metadata: [
                        HKMetadataKeyExternalUUID: insulinSample.id,
                        HKMetadataKeySyncIdentifier: insulinSample.id,
                        HKMetadataKeySyncVersion: 1,
                        HKMetadataKeyInsulinDeliveryReason: deliveryReason.rawValue,
                        AppleHealthConfig.freeAPSMetaKey: true
                    ]
                )
            }

            guard insulinSamples.isNotEmpty else {
                debug(.service, "No insulin samples available for upload.")
                return
            }

            // Attempt to save the insulin samples to Apple Health
            try await healthKitStore.save(insulinSamples)
            debug(.service, "Successfully stored \(insulinSamples.count) insulin samples in HealthKit.")

            // After successful upload, update the isUploadedToHealth flag in Core Data
            await updateInsulinAsUploaded(insulin)

        } catch {
            debug(.service, "Failed to upload insulin samples to HealthKit: \(error.localizedDescription)")
        }
    }

    private func updateInsulinAsUploaded(_ insulin: [PumpHistoryEvent]) async {
        await backgroundContext.perform {
            let ids = insulin.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToHealth = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToHealth: \(error.userInfo)"
                )
            }
        }
    }

    // Delete Glucose/Carbs/Insulin

    func deleteGlucose(syncID: String) async {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthBGObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType)
        else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: syncID
        )

        do {
            try await deleteObjects(of: sampleType, predicate: predicate)
            debug(.service, "Successfully deleted glucose sample with syncID: \(syncID)")
        } catch {
            warning(.service, "Failed to delete glucose sample with syncID: \(syncID)", error: error)
        }
    }

    func deleteMealData(byID id: String, sampleType: HKSampleType) async {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: id
        )

        do {
            try await deleteObjects(of: sampleType, predicate: predicate)
            debug(.service, "Successfully deleted \(sampleType) with syncID: \(id)")
        } catch {
            warning(.service, "Failed to delete carbs sample with syncID: \(id)", error: error)
        }
    }

    private func deleteObjects(of sampleType: HKSampleType, predicate: NSPredicate) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthKitStore.deleteObjects(of: sampleType, predicate: predicate) { success, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    // Observer that notifies when new Glucose values arrive in Apple Health

    func createBGObserver() {
        guard settingsManager.settings.useAppleHealth else { return }

        guard let bgType = AppleHealthConfig.healthBGObject else {
            warning(.service, "Can not create HealthKit Observer, because unable to get the Blood Glucose type")
            return
        }

        let query = HKObserverQuery(sampleType: bgType, predicate: nil) { [weak self] _, _, observerError in
            guard let self = self else { return }
            debug(.service, "Execute HealthKit observer query for loading increment samples")
            guard observerError == nil else {
                warning(.service, "Error during execution of HealthKit Observer's query", error: observerError!)
                return
            }

            if let incrementQuery = self.getBloodGlucoseHKQuery(predicate: self.loadBGPredicate) {
                debug(.service, "Create increment query")
                self.healthKitStore.execute(incrementQuery)
            }
        }
        healthKitStore.execute(query)
        debug(.service, "Create Observer for Blood Glucose")
    }

    func enableBackgroundDelivery() {
        guard settingsManager.settings.useAppleHealth else {
            healthKitStore.disableAllBackgroundDelivery { _, _ in }
            return }

        guard let bgType = AppleHealthConfig.healthBGObject else {
            warning(
                .service,
                "Can not create background delivery, because unable to get the Blood Glucose type"
            )
            return
        }

        healthKitStore.enableBackgroundDelivery(for: bgType, frequency: .immediate) { status, error in
            guard error == nil else {
                warning(.service, "Can not enable background delivery", error: error)
                return
            }
            debug(.service, "Background delivery status is \(status)")
        }
    }

    private func getBloodGlucoseHKQuery(predicate: NSPredicate) -> HKQuery? {
        guard let sampleType = AppleHealthConfig.healthBGObject else { return nil }

        let query = HKAnchoredObjectQuery(
            type: sampleType,
            predicate: predicate,
            anchor: lastBloodGlucoseQueryAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, addedObjects, _, anchor, _ in
            guard let self = self else { return }
            self.processQueue.async {
                debug(.service, "AnchoredQuery did execute")

                self.lastBloodGlucoseQueryAnchor = anchor

                // Added objects
                if let bgSamples = addedObjects as? [HKQuantitySample],
                   bgSamples.isNotEmpty
                {
                    self.prepareBGSamplesToPublisherFetch(bgSamples)
                }
            }
        }
        return query
    }

    private func prepareBGSamplesToPublisherFetch(_ samples: [HKQuantitySample]) {
        dispatchPrecondition(condition: .onQueue(processQueue))

        newGlucose += samples
            .compactMap { sample -> HealthKitSample? in
                let fromTrio = sample.metadata?[AppleHealthConfig.freeAPSMetaKey] as? Bool ?? false
                guard !fromTrio else { return nil }
                return HealthKitSample(
                    healthKitId: sample.uuid.uuidString,
                    date: sample.startDate,
                    glucose: Int(round(sample.quantity.doubleValue(for: .milligramsPerDeciliter)))
                )
            }
            .map { sample in
                BloodGlucose(
                    _id: sample.healthKitId,
                    sgv: sample.glucose,
                    direction: nil,
                    date: Decimal(Int(sample.date.timeIntervalSince1970) * 1000),
                    dateString: sample.date,
                    unfiltered: Decimal(sample.glucose),
                    filtered: nil,
                    noise: nil,
                    glucose: sample.glucose,
                    type: "sgv"
                )
            }
            .filter { $0.dateString >= Date().addingTimeInterval(-1.days.timeInterval) }

        newGlucose = newGlucose.removeDublicates()
    }

    // MARK: - GlucoseSource

    var glucoseManager: FetchGlucoseManager?
    var cgmManager: CGMManagerUI?

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.success([]))
                return
            }

            self.processQueue.async {
                guard self.settingsManager.settings.useAppleHealth else {
                    promise(.success([]))
                    return
                }

                // Remove old BGs
                self.newGlucose = self.newGlucose
                    .filter { $0.dateString >= Date().addingTimeInterval(-1.days.timeInterval) }
                // Get actual BGs (beetwen Date() - 1 day and Date())
                let actualGlucose = self.newGlucose
                    .filter { $0.dateString <= Date() }
                // Update newGlucose
                self.newGlucose = self.newGlucose
                    .filter { !actualGlucose.contains($0) }

                //  debug(.service, "Actual glucose is \(actualGlucose)")

                //  debug(.service, "Current state of newGlucose is \(self.newGlucose)")

                promise(.success(actualGlucose))
            }
        }
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }

    // - MARK Carbs function

    func deleteCarbs(syncID: String, fpuID: String) {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthCarbObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType)
        else { return }

        print("meals 4: ID: " + syncID + " FPU ID: " + fpuID)

        if syncID != "" {
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                operatorType: .equalTo,
                value: syncID
            )

            healthKitStore.deleteObjects(of: sampleType, predicate: predicate) { _, _, error in
                guard let error = error else { return }
                warning(.service, "Cannot delete sample with syncID: \(syncID)", error: error)
            }
        }

        if fpuID != "" {
            // processQueue.async {
            let recentCarbs: [CarbsEntry] = carbsStorage.recent()
            let ids = recentCarbs.filter { $0.fpuID == fpuID }.compactMap(\.id)
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                allowedValues: ids
            )
            print("found IDs: " + ids.description)
            healthKitStore.deleteObjects(of: sampleType, predicate: predicate) { _, _, error in
                guard let error = error else { return }
                warning(.service, "Cannot delete sample with fpuID: \(fpuID)", error: error)
            }
            // }
        }
    }

    // - MARK Insulin function

    func deleteInsulin(syncID: String) {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthInsulinObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType)
        else { return }

        processQueue.async {
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                operatorType: .equalTo,
                value: syncID
            )

            self.healthKitStore.deleteObjects(of: sampleType, predicate: predicate) { _, _, error in
                guard let error = error else { return }
                warning(.service, "Cannot delete sample with syncID: \(syncID)", error: error)
            }
        }
    }
}

enum HealthKitPermissionRequestStatus {
    case needRequest
    case didRequest
}

enum HKError: Error {
    // HealthKit work only iPhone (not on iPad)
    case notAvailableOnCurrentDevice
    // Some data can be not available on current iOS-device
    case dataNotAvailable
}

private struct InsulinBolus {
    var id: String
    var amount: Decimal
    var date: Date
}

private struct InsulinBasal {
    var id: String
    var amount: Decimal
    var startDelivery: Date
    var endDelivery: Date
}
