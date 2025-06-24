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
    static let TrioInsulinType = "Trio Insulin Type"
}

final class BaseHealthKitManager: HealthKitManager, Injectable {
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var healthKitStore: HKHealthStore!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!

    private var backgroundContext = CoreDataStack.shared.newTaskContext()

    // Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseHealthKitManager.queue", qos: .background)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    var isAvailableOnCurrentDevice: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init(resolver: Resolver) {
        injectServices(resolver)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.uploadGlucose()
                }
            }
            .store(in: &subscriptions)

        registerHandlers()

        guard isAvailableOnCurrentDevice,
              AppleHealthConfig.healthBGObject != nil else { return }

        debug(.service, "HealthKitManager did create")
    }

    private func registerHandlers() {
        coreDataPublisher?.filteredByEntityName("PumpEventStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.uploadInsulin()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filteredByEntityName("CarbEntryStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.uploadCarbs()
            }
        }.store(in: &subscriptions)

        // This works only for manual Glucose
        coreDataPublisher?.filteredByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.uploadGlucose()
            }
        }.store(in: &subscriptions)
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
        do {
            let glucose = try await glucoseStorage.getGlucoseNotYetUploadedToHealth()
            await uploadGlucose(glucose)

            let manualGlucose = try await glucoseStorage.getManualGlucoseNotYetUploadedToHealth()
            await uploadGlucose(manualGlucose)
        } catch {
            debug(
                .service,
                "\(DebuggingIdentifiers.failed) Error fetching glucose for health upload: \(error)"
            )
        }
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
                        AppleHealthConfig.TrioInsulinType: deviceDataManager?.pumpManager?.status.insulinType?.title ?? ""
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
            debug(.service, "Failed to upload glucose samples to HealthKit: \(error)")
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
        do {
            let carbs = try await carbsStorage.getCarbsNotYetUploadedToHealth()
            await uploadCarbs(carbs)
        } catch {
            debug(
                .service,
                "\(DebuggingIdentifiers.failed) Error fetching carbs for health upload: \(error)"
            )
        }
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

                // Carbs Sample (only if value is greater than 0)
                let carbValue = allSamples.carbs
                if carbValue > 0 {
                    let carbSample = HKQuantitySample(
                        type: carbSampleType,
                        quantity: HKQuantity(unit: .gram(), doubleValue: Double(carbValue)),
                        start: startDate,
                        end: startDate,
                        metadata: [
                            HKMetadataKeyExternalUUID: id,
                            HKMetadataKeySyncIdentifier: id,
                            HKMetadataKeySyncVersion: 1
                        ]
                    )
                    samples.append(carbSample)
                }

                // Fat Sample (only if value is greater than 0)
                if let fatValue = allSamples.fat, fatValue > 0 {
                    let fatSample = HKQuantitySample(
                        type: fatSampleType,
                        quantity: HKQuantity(unit: .gram(), doubleValue: Double(fatValue)),
                        start: startDate,
                        end: startDate,
                        metadata: [
                            HKMetadataKeyExternalUUID: fpuID,
                            HKMetadataKeySyncIdentifier: fpuID,
                            HKMetadataKeySyncVersion: 1
                        ]
                    )
                    samples.append(fatSample)
                }

                // Protein Sample (only if value is greater than 0)
                if let proteinValue = allSamples.protein, proteinValue > 0 {
                    let proteinSample = HKQuantitySample(
                        type: proteinSampleType,
                        quantity: HKQuantity(unit: .gram(), doubleValue: Double(proteinValue)),
                        start: startDate,
                        end: startDate,
                        metadata: [
                            HKMetadataKeyExternalUUID: fpuID,
                            HKMetadataKeySyncIdentifier: fpuID,
                            HKMetadataKeySyncVersion: 1
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
            debug(.service, "Failed to upload carb samples to HealthKit: \(error)")
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
        do {
            let events = try await pumpHistoryStorage.getPumpHistoryNotYetUploadedToHealth()
            await uploadInsulin(events)
        } catch {
            debug(
                .service,
                "\(DebuggingIdentifiers.failed) Error fetching insulin events for health upload: \(error)"
            )
        }
    }

    func uploadInsulin(_ insulinEvents: [PumpHistoryEvent]) async {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthInsulinObject,
              checkWriteToHealthPermissions(objectTypeToHealthStore: sampleType),
              insulinEvents.isNotEmpty else { return }

        do {
            let fetchedInsulinEntries = try await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: PumpEventStored.self,
                onContext: backgroundContext,
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate.pumpHistoryLast24h,
                    NSPredicate(format: "tempBasal != nil")
                ]),
                key: "timestamp",
                ascending: true,
                batchSize: 50
            )

            var insulinSamples: [HKQuantitySample] = []

            try await backgroundContext.perform {
                guard let existingTempBasalEntries = fetchedInsulinEntries as? [PumpEventStored] else {
                    throw CoreDataError.fetchError(function: #function, file: #file)
                }

                for event in insulinEvents {
                    switch event.type {
                    case .bolus:
                        // For bolus events, create a HealthKit sample directly
                        if let sample = self.createSample(for: event, sampleType: sampleType) {
                            debug(.service, "Created HealthKit sample for bolus entry: \(sample)")
                            insulinSamples.append(sample)
                        }
                    case .tempBasal:
                        // For temp basal events, process them and adjust overlapping durations if necessary
                        guard let duration = event.duration, let amount = event.amount else { continue }

                        let value = (Decimal(duration) / 60.0) * amount
                        let valueRounded = self.deviceDataManager?.pumpManager?
                            .roundToSupportedBolusVolume(units: Double(value)) ?? Double(value)

                        // Use binary search for efficient lookup of matching entry
                        if let matchingIndex = self.binarySearch(entries: existingTempBasalEntries, timestamp: event.timestamp) {
                            let predecessorIndex = matchingIndex - 1

                            if predecessorIndex >= 0 {
                                let predecessorEntry = existingTempBasalEntries[predecessorIndex]

                                if let adjustedSample = self.processPredecessorEntry(
                                    predecessorEntry,
                                    nextEventTimestamp: event.timestamp,
                                    sampleType: sampleType
                                ) {
                                    insulinSamples.append(adjustedSample)
                                }
                            }

                            let newEvent = PumpHistoryEvent(
                                id: event.id,
                                type: .tempBasal,
                                timestamp: event.timestamp,
                                amount: Decimal(valueRounded),
                                duration: event.duration
                            )

                            if let sample = self.createSample(for: newEvent, sampleType: sampleType) {
                                debug(.service, "Created HealthKit sample for initial temp basal entry: \(sample)")
                                insulinSamples.append(sample)
                            }
                        }

                    default:
                        break
                    }
                }
            }

            do {
                guard insulinSamples.isNotEmpty else {
                    debug(.service, "No insulin samples available for upload.")
                    return
                }

                try await healthKitStore.save(insulinSamples)
                debug(.service, "Successfully stored \(insulinSamples.count) insulin samples in HealthKit.")
                await updateInsulinAsUploaded(insulinEvents)
            } catch {
                debug(.service, "Failed to upload insulin samples to HealthKit: \(error)")
            }
        } catch {
            debug(.service, "\(DebuggingIdentifiers.failed) Error fetching temp basal entries: \(error)")
        }
    }

    // Helper function to perform binary search on the sorted entries by timestamp
    private func binarySearch(entries: [PumpEventStored], timestamp: Date) -> Int? {
        var lowerBound = 0
        var upperBound = entries.count - 1

        while lowerBound <= upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            guard let midTimestamp = entries[midIndex].timestamp else { return nil }

            if midTimestamp == timestamp {
                return midIndex
            } else if midTimestamp < timestamp {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex - 1
            }
        }

        return nil
    }

    // Helper function to create a HealthKit sample from a PumpHistoryEvent
    private func createSample(
        for event: PumpHistoryEvent,
        sampleType: HKQuantityType
    ) -> HKQuantitySample? {
        // Ensure the event has a valid insulin amount
        guard let insulinValue = event.amount else { return nil }

        // Determine the insulin delivery reason based on the event type
        let deliveryReason: HKInsulinDeliveryReason
        switch event.type {
        case .bolus:
            deliveryReason = .bolus
        case .tempBasal:
            deliveryReason = .basal
        default:
            return nil
        }

        // Calculate the end date based on the event duration
        let endDate = event.timestamp.addingTimeInterval(TimeInterval(minutes: Double(event.duration ?? 0)))

        // Create the HealthKit quantity sample with the appropriate metadata
        let sample = HKQuantitySample(
            type: sampleType,
            quantity: HKQuantity(unit: .internationalUnit(), doubleValue: Double(insulinValue)),
            start: event.timestamp,
            end: endDate,
            metadata: [
                HKMetadataKeyExternalUUID: event.id,
                HKMetadataKeySyncIdentifier: event.id,
                HKMetadataKeySyncVersion: 1,
                HKMetadataKeyInsulinDeliveryReason: deliveryReason.rawValue,
                AppleHealthConfig.TrioInsulinType: deviceDataManager?.pumpManager?.status.insulinType?.title ?? ""
            ]
        )

        return sample
    }

    // Helper function to process a predecessor temp basal entry and adjust overlapping durations
    private func processPredecessorEntry(
        _ predecessorEntry: PumpEventStored,
        nextEventTimestamp: Date,
        sampleType: HKQuantityType
    ) -> HKQuantitySample? {
        // Ensure the predecessor entry has the necessary data
        guard let predecessorTimestamp = predecessorEntry.timestamp,
              let predecessorEntryId = predecessorEntry.id else { return nil }

        // Calculate the original end date of the predecessor temp basal
        let predecessorDurationMinutes = predecessorEntry.tempBasal?.duration ?? 0
        let predecessorEndDate = predecessorTimestamp.addingTimeInterval(TimeInterval(predecessorDurationMinutes * 60))

        // Check if the predecessor temp basal overlaps with the next event
        if predecessorEndDate > nextEventTimestamp {
            // Adjust the end date to the start of the next event to prevent overlap
            let adjustedEndDate = nextEventTimestamp
            // Precise duration in seconds
            let adjustedDuration = adjustedEndDate.timeIntervalSince(predecessorTimestamp)
            // Precise duration in hours
            let adjustedDurationHours = adjustedDuration / 3600

            // Calculate the insulin rate and adjusted delivered units
            let predecessorEntryRate = predecessorEntry.tempBasal?.rate?.doubleValue ?? 0
            let adjustedDeliveredUnits = adjustedDurationHours * predecessorEntryRate
            let adjustedDeliveredUnitsRounded = deviceDataManager?.pumpManager?
                .roundToSupportedBolusVolume(units: adjustedDeliveredUnits) ?? adjustedDeliveredUnits

            // Create the HealthKit quantity sample with the appropriate metadata
            // Intentionally do it here manually and do not use `createSample()` to handle utmost precise `end`.
            let sample = HKQuantitySample(
                type: sampleType,
                quantity: HKQuantity(unit: .internationalUnit(), doubleValue: Double(adjustedDeliveredUnitsRounded)),
                start: predecessorTimestamp,
                end: adjustedEndDate,
                metadata: [
                    HKMetadataKeyExternalUUID: predecessorEntryId,
                    HKMetadataKeySyncIdentifier: predecessorEntryId,
                    HKMetadataKeySyncVersion: 2, // set the version # to 2, as we update an entry. initial version is 1.
                    HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.basal.rawValue,
                    AppleHealthConfig.TrioInsulinType: deviceDataManager?.pumpManager?.status.insulinType?.title ?? ""
                ]
            )

            debug(.service, "Created HealthKit sample for adjusted temp basal entry: \(sample)")

            // Create and return the HealthKit sample for the adjusted event
            return sample
        }

        // If there is no overlap, no adjustment is needed
        return nil
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
