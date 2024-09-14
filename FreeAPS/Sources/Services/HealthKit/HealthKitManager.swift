import Combine
import CoreData
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import Swinject

protocol HealthKitManager {
    /// Check all needed permissions
    /// Return false if one or more permissions are deny or not choosen
    var hasGrantedFullWritePermissions: Bool { get }
    /// Check availability to save data of BG type to Health store
    func hasGlucoseWritePermission() -> Bool
    /// Requests user to give permissions on using HealthKit
    func requestPermission() async throws -> Bool
    /// Checks whether permissions are granted for Trio to write to Health
    func checkWriteToHealthPermissions(objectTypeToHealthStore: HKObjectType) -> Bool
    /// Save blood glucose to Health store
    func uploadGlucose() async
    /// Save carbs to Health store
    func uploadCarbs() async
    /// Save Insulin to Health store
    func uploadInsulin() async
    /// Delete glucose with syncID
    func deleteGlucose(syncID: String) async
    /// delete carbs with syncID
    func deleteMealData(byID id: String, sampleType: HKSampleType) async
    /// delete insulin with syncID
    func deleteInsulin(syncID: String) async
}

public enum AppleHealthConfig {
    // unwraped HKObjects
    static var writePermissions: Set<HKSampleType> {
        Set([healthBGObject, healthCarbObject, healthFatObject, healthProteinObject, healthInsulinObject].compactMap { $0 }) }

    // link to object in HealthKit
    static let healthBGObject = HKObjectType.quantityType(forIdentifier: .bloodGlucose)
    static let healthCarbObject = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
    static let healthFatObject = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)
    static let healthProteinObject = HKObjectType.quantityType(forIdentifier: .dietaryProtein)
    static let healthInsulinObject = HKObjectType.quantityType(forIdentifier: .insulinDelivery)

    // MetaDataKey of Trio data in HealthStore
    static let TrioMetaDataKey = "TrioMetaDataKey"
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

    var isAvailableOnCurrentDevice: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        guard isAvailableOnCurrentDevice,
              AppleHealthConfig.healthBGObject != nil else { return }

        carbsStorage.delegate = self
        pumpHistoryStorage.delegate = self

        debug(.service, "HealthKitManager did create")
    }

    func checkWriteToHealthPermissions(objectTypeToHealthStore: HKObjectType) -> Bool {
        healthKitStore.authorizationStatus(for: objectTypeToHealthStore) == .sharingAuthorized
    }

    var hasGrantedFullWritePermissions: Bool {
        Set(AppleHealthConfig.writePermissions.map { healthKitStore.authorizationStatus(for: $0) })
            .intersection([.sharingDenied, .notDetermined])
            .isEmpty
    }

    func hasGlucoseWritePermission() -> Bool {
        AppleHealthConfig.healthBGObject.map { checkWriteToHealthPermissions(objectTypeToHealthStore: $0) } ?? false
    }

    func requestPermission() async throws -> Bool {
        guard isAvailableOnCurrentDevice else {
            throw HKError.notAvailableOnCurrentDevice
        }

        return try await withCheckedThrowingContinuation { continuation in
            healthKitStore.requestAuthorization(
                toShare: AppleHealthConfig.writePermissions,
                read: nil
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
              checkWriteToHealthPermissions(objectTypeToHealthStore: sampleType),
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
                        AppleHealthConfig.TrioMetaDataKey: UUID().uuidString
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
              checkWriteToHealthPermissions(objectTypeToHealthStore: carbSampleType),
              carbs.isNotEmpty
        else { return }

        do {
            var samples: [HKQuantitySample] = []

            // Create HealthKit samples for carbs, fat, and protein
            for allSamples in carbs {
                guard let id = allSamples.id else { continue }
                let fpuID = allSamples.fpuID ?? id

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
                        AppleHealthConfig.TrioMetaDataKey: UUID().uuidString
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
                            HKMetadataKeyExternalUUID: fpuID,
                            HKMetadataKeySyncIdentifier: fpuID,
                            HKMetadataKeySyncVersion: 1,
                            AppleHealthConfig.TrioMetaDataKey: UUID().uuidString
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
                            HKMetadataKeyExternalUUID: fpuID,
                            HKMetadataKeySyncIdentifier: fpuID,
                            HKMetadataKeySyncVersion: 1,
                            AppleHealthConfig.TrioMetaDataKey: UUID().uuidString
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
              checkWriteToHealthPermissions(objectTypeToHealthStore: sampleType),
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
                        AppleHealthConfig.TrioMetaDataKey: UUID().uuidString
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
              checkWriteToHealthPermissions(objectTypeToHealthStore: sampleType)
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
        guard settingsManager.settings.useAppleHealth else { return }

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

    func deleteInsulin(syncID: String) async {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthInsulinObject,
              checkWriteToHealthPermissions(objectTypeToHealthStore: sampleType)
        else {
            debug(.service, "HealthKit permissions are not available for insulin deletion.")
            return
        }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: syncID
        )

        do {
            try await deleteObjects(of: sampleType, predicate: predicate)
            debug(.service, "Successfully deleted insulin sample with syncID: \(syncID)")
        } catch {
            warning(.service, "Failed to delete insulin sample with syncID: \(syncID)", error: error)
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
