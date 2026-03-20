import Combine
import CoreData
import CryptoKit
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import Swinject
import TidepoolServiceKit
import UIKit

protocol TidepoolManager {
    func addTidepoolService(service: Service)
    func getTidepoolServiceUI() -> ServiceUI?
    func getTidepoolPluginHost() -> PluginHost?
    func uploadCarbs() async
    func deleteCarbs(withSyncId id: UUID, carbs: Decimal, at: Date, enteredBy: String)
    func uploadInsulin() async
    func deleteInsulin(withSyncId id: String, amount: Decimal, at: Date)
    func uploadGlucose() async
    func uploadSettings() async
    func forceTidepoolDataUpload()
}

final class BaseTidepoolManager: TidepoolManager, Injectable {
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var pluginManager: PluginManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var settingsManager: SettingsManager!

    // Lazy access to avoid circular dependency (TidepoolManager ↔ FetchGlucoseManager)
    private var resolver: Resolver?

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")

    /// Pending debounce work item for settings upload; cancelled and rescheduled
    /// each time an observer fires, so rapid changes coalesce into one upload.
    /// - Important: Only access from `processQueue` to ensure thread safety.
    private var pendingSettingsUpload: DispatchWorkItem?

    /// Delay before a debounced settings upload fires.
    private static let settingsUploadDebounceDelay: TimeInterval = 1.5

    /// Last-seen therapy-relevant TrioSettings values.
    /// Used to filter `settingsDidChange` so UI-only changes don't trigger uploads.
    private var lastClosedLoop: Bool?
    private var lastUnits: GlucoseUnits?
    private var tidepoolService: RemoteDataService? {
        didSet {
            if let tidepoolService = tidepoolService {
                rawTidepoolManager = tidepoolService.rawValue
            } else {
                rawTidepoolManager = nil
            }
        }
    }

    private var backgroundContext = CoreDataStack.shared.newTaskContext()

    // Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseTidepoolManager.queue", qos: .background)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    @PersistedProperty(key: "TidepoolState") var rawTidepoolManager: Service.RawValue?

    init(resolver: Resolver) {
        self.resolver = resolver
        injectServices(resolver)
        loadTidepoolManager()

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
    }

    /// Loads the Tidepool service from saved state
    fileprivate func loadTidepoolManager() {
        if let rawTidepoolManager = rawTidepoolManager {
            tidepoolService = tidepoolServiceFromRaw(rawTidepoolManager)
            tidepoolService?.serviceDelegate = self
            tidepoolService?.stateDelegate = self
        }
    }

    /// Returns the Tidepool service UI if available
    func getTidepoolServiceUI() -> ServiceUI? {
        tidepoolService as? ServiceUI
    }

    /// Returns the Tidepool plugin host
    func getTidepoolPluginHost() -> PluginHost? {
        self as PluginHost
    }

    /// Adds a Tidepool service
    func addTidepoolService(service: Service) {
        tidepoolService = service as? RemoteDataService
    }

    /// Loads the Tidepool service from raw stored data
    private func tidepoolServiceFromRaw(_ rawValue: [String: Any]) -> RemoteDataService? {
        let serviceType = TidepoolService.self
        guard let rawState = rawValue["state"] as? Service.RawStateValue
        else { return nil }

        if let service = serviceType.init(rawState: rawState) {
            return service as RemoteDataService
        }
        return nil
    }

    /// Registers handlers for Core Data changes
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

        // Register for settings that aren't saved from a single editor screen
        broadcaster.register(SettingsObserver.self, observer: self)
        broadcaster.register(PreferencesObserver.self, observer: self)
    }

    func sourceInfo() -> [String: Any]? {
        nil
    }

    /// Forces a full data upload to Tidepool
    func forceTidepoolDataUpload() {
        Task {
            await uploadInsulin()
            await uploadCarbs()
            await uploadGlucose()
            await uploadSettings()
        }
    }
}

extension BaseTidepoolManager: ServiceDelegate {
    var hostIdentifier: String {
        "org.nightscout.Trio"
    }

    var hostVersion: String {
        var semanticVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String

        while semanticVersion.split(separator: ".").count < 3 {
            semanticVersion += ".0"
        }

        semanticVersion += "+\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String)"

        return semanticVersion
    }

    func issueAlert(_: LoopKit.Alert) {}

    func retractAlert(identifier _: LoopKit.Alert.Identifier) {}

    func enactRemoteOverride(name _: String, durationTime _: TimeInterval?, remoteAddress _: String) async throws {}

    func cancelRemoteOverride() async throws {}

    func deliverRemoteCarbs(
        amountInGrams _: Double,
        absorptionTime _: TimeInterval?,
        foodType _: String?,
        startDate _: Date?
    ) async throws {}

    func deliverRemoteBolus(amountInUnits _: Double) async throws {}
}

/// Carb Upload and Deletion Functionality
extension BaseTidepoolManager {
    func uploadCarbs() async {
        do {
            try uploadCarbs(await carbsStorage.getCarbsNotYetUploadedToTidepool())
        } catch {
            debug(.service, "\(DebuggingIdentifiers.failed) Failed to upload carbs with error: \(error)")
        }
    }

    func uploadCarbs(_ carbs: [CarbsEntry]) {
        guard !carbs.isEmpty, let tidepoolService = self.tidepoolService else { return }

        processQueue.async {
            carbs.chunks(ofCount: tidepoolService.carbDataLimit ?? 100).forEach { chunk in

                let syncCarb: [SyncCarbObject] = Array(chunk).map {
                    $0.convertSyncCarb()
                }
                tidepoolService.uploadCarbData(created: syncCarb, updated: [], deleted: []) { result in
                    switch result {
                    case let .failure(error):
                        debug(.nightscout, "Error synchronizing carbs data with Tidepool: \(String(describing: error))")
                    case .success:
                        debug(.nightscout, "Success synchronizing carbs data. Upload to Tidepool complete.")
                        // After successful upload, update the isUploadedToTidepool flag in Core Data
                        Task {
                            await self.updateCarbsAsUploaded(carbs)
                        }
                    }
                }
            }
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
                    result.isUploadedToTidepool = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToTidepool: \(error.userInfo)"
                )
            }
        }
    }

    func deleteCarbs(withSyncId id: UUID, carbs: Decimal, at: Date, enteredBy: String) {
        guard let tidepoolService = self.tidepoolService else { return }

        processQueue.async {
            let syncCarb: [SyncCarbObject] = [SyncCarbObject(
                absorptionTime: nil,
                createdByCurrentApp: true,
                foodType: nil,
                grams: Double(carbs),
                startDate: at,
                uuid: id,
                provenanceIdentifier: enteredBy,
                syncIdentifier: id.uuidString,
                syncVersion: nil,
                userCreatedDate: nil,
                userUpdatedDate: nil,
                userDeletedDate: nil,
                operation: LoopKit.Operation.delete,
                addedDate: nil,
                supercededDate: nil
            )]

            tidepoolService.uploadCarbData(created: [], updated: [], deleted: syncCarb) { result in
                switch result {
                case let .failure(error):
                    debug(.nightscout, "Error synchronizing carbs data with Tidepool: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing carbs data. Upload to Tidepool complete.")
                }
            }
        }
    }
}

/// Insulin Upload and Deletion Functionality
extension BaseTidepoolManager {
    func uploadInsulin() async {
        do {
            let events = try await pumpHistoryStorage.getPumpHistoryNotYetUploadedToTidepool()
            await uploadDose(events)
        } catch {
            debug(.service, "Error fetching pump history: \(error)")
        }
    }

    func uploadDose(_ events: [PumpHistoryEvent]) async {
        guard !events.isEmpty, let tidepoolService = self.tidepoolService else { return }

        do {
            // Fetch all temp basal entries from Core Data for the last 24 hours
            let results = try await CoreDataStack.shared.fetchEntitiesAsync(
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

            // Ensure that the processing happens within the background context for thread safety
            try await backgroundContext.perform {
                guard let existingTempBasalEntries = results as? [PumpEventStored] else {
                    throw CoreDataError.fetchError(function: #function, file: #file)
                }

                let insulinDoseEvents: [DoseEntry] = events.reduce([]) { result, event in
                    var result = result
                    switch event.type {
                    case .tempBasal:
                        result
                            .append(
                                contentsOf: self
                                    .processTempBasalEvent(event, existingTempBasalEntries: existingTempBasalEntries)
                            )
                    case .bolus:
                        let bolusDoseEntry = DoseEntry(
                            type: .bolus,
                            startDate: event.timestamp,
                            endDate: event.timestamp,
                            value: Double(event.amount!),
                            unit: .units,
                            deliveredUnits: nil,
                            syncIdentifier: event.id,
                            scheduledBasalRate: nil,
                            insulinType: self.apsManager.pumpManager?.status.insulinType ?? nil,
                            automatic: event.isSMB ?? true,
                            manuallyEntered: event.isExternal ?? false
                        )
                        result.append(bolusDoseEntry)
                    default:
                        break
                    }
                    return result
                }

                debug(.service, "TIDEPOOL DOSE ENTRIES: \(insulinDoseEvents)")

                let pumpEvents: [PersistedPumpEvent] = events.compactMap { event -> PersistedPumpEvent? in
                    if let pumpEventType = event.type.mapEventTypeToPumpEventType() {
                        let dose: DoseEntry? = switch pumpEventType {
                        case .suspend:
                            DoseEntry(suspendDate: event.timestamp, automatic: true)
                        case .resume:
                            DoseEntry(resumeDate: event.timestamp, automatic: true)
                        default:
                            nil
                        }

                        return PersistedPumpEvent(
                            date: event.timestamp,
                            persistedDate: event.timestamp,
                            dose: dose,
                            isUploaded: true,
                            objectIDURL: URL(string: "x-coredata:///PumpEvent/\(event.id)")!,
                            raw: event.id.data(using: .utf8),
                            title: event.note,
                            type: pumpEventType
                        )
                    } else {
                        return nil
                    }
                }

                self.processQueue.async {
                    tidepoolService.uploadDoseData(created: insulinDoseEvents, deleted: []) { result in
                        switch result {
                        case let .failure(error):
                            debug(.nightscout, "Error synchronizing dose data with Tidepool: \(String(describing: error))")
                        case .success:
                            debug(.nightscout, "Success synchronizing dose data. Upload to Tidepool complete.")
                            Task {
                                let insulinEvents = events.filter {
                                    $0.type == .tempBasal || $0.type == .tempBasalDuration || $0.type == .bolus
                                }
                                await self.updateInsulinAsUploaded(insulinEvents)
                            }
                        }
                    }

                    tidepoolService.uploadPumpEventData(pumpEvents) { result in
                        switch result {
                        case let .failure(error):
                            debug(.nightscout, "Error synchronizing pump events data: \(String(describing: error))")
                        case .success:
                            debug(.nightscout, "Success synchronizing pump events data. Upload to Tidepool complete.")
                            Task {
                                let pumpEventType = events.map { $0.type.mapEventTypeToPumpEventType() }
                                let pumpEvents = events.filter { _ in pumpEventType.contains(pumpEventType) }

                                await self.updateInsulinAsUploaded(pumpEvents)
                            }
                        }
                    }
                }
            }
        } catch {
            debug(.service, "Error fetching temp basal entries: \(error)")
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
                    result.isUploadedToTidepool = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToTidepool: \(error.userInfo)"
                )
            }
        }
    }

    func deleteInsulin(withSyncId id: String, amount: Decimal, at: Date) {
        guard let tidepoolService = self.tidepoolService else { return }

        // must be an array here, because `tidepoolService.uploadDoseData` expects a `deleted` array
        let doseDataToDelete: [DoseEntry] = [DoseEntry(
            type: .bolus,
            startDate: at,
            value: Double(amount),
            unit: .units,
            syncIdentifier: id
        )]

        processQueue.async {
            tidepoolService.uploadDoseData(created: [], deleted: doseDataToDelete) { result in
                switch result {
                case let .failure(error):
                    debug(.nightscout, "Error synchronizing Dose delete data: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing Dose delete data")
                }
            }
        }
    }
}

/// Insulin Helper Functions
extension BaseTidepoolManager {
    private func processTempBasalEvent(
        _ event: PumpHistoryEvent,
        existingTempBasalEntries: [PumpEventStored]
    ) -> [DoseEntry] {
        var insulinDoseEvents: [DoseEntry] = []

        backgroundContext.performAndWait {
            // Loop through the pump history events within the background context
            guard let duration = event.duration, let amount = event.amount,
                  let currentBasalRate = self.getCurrentBasalRate()
            else {
                return
            }
            let value = (Decimal(duration) / 60.0) * amount

            // Find the corresponding temp basal entry in existingTempBasalEntries
            if let matchingEntryIndex = existingTempBasalEntries.firstIndex(where: { $0.timestamp == event.timestamp }) {
                // Check for a predecessor (the entry before the matching entry)
                let predecessorIndex = matchingEntryIndex - 1
                if predecessorIndex >= 0 {
                    let predecessorEntry = existingTempBasalEntries[predecessorIndex]
                    if let predecessorTimestamp = predecessorEntry.timestamp,
                       let predecessorEntrySyncIdentifier = predecessorEntry.id
                    {
                        let predecessorEndDate = predecessorTimestamp
                            .addingTimeInterval(TimeInterval(
                                Int(predecessorEntry.tempBasal?.duration ?? 0) *
                                    60
                            )) // parse duration to minutes

                        // If the predecessor's end date is later than the current event's start date, adjust it
                        if predecessorEndDate > event.timestamp {
                            let adjustedEndDate = event.timestamp
                            let adjustedDuration = adjustedEndDate.timeIntervalSince(predecessorTimestamp)
                            let adjustedDeliveredUnits = (adjustedDuration / 3600) *
                                Double(truncating: predecessorEntry.tempBasal?.rate ?? 0)

                            // Create updated predecessor dose entry
                            let updatedPredecessorEntry = DoseEntry(
                                type: .tempBasal,
                                startDate: predecessorTimestamp,
                                endDate: adjustedEndDate,
                                value: adjustedDeliveredUnits,
                                unit: .units,
                                deliveredUnits: adjustedDeliveredUnits,
                                syncIdentifier: predecessorEntrySyncIdentifier,
                                insulinType: self.apsManager.pumpManager?.status.insulinType ?? nil,
                                automatic: true,
                                manuallyEntered: false,
                                isMutable: false
                            )
                            // Add the updated predecessor entry to the result
                            insulinDoseEvents.append(updatedPredecessorEntry)
                        }
                    }
                }

                // Create a new dose entry for the current event
                let currentEndDate = event.timestamp.addingTimeInterval(TimeInterval(minutes: Double(duration)))
                let newDoseEntry = DoseEntry(
                    type: .tempBasal,
                    startDate: event.timestamp,
                    endDate: currentEndDate,
                    value: Double(value),
                    unit: .units,
                    deliveredUnits: Double(value),
                    syncIdentifier: event.id,
                    scheduledBasalRate: HKQuantity(
                        unit: .internationalUnitsPerHour,
                        doubleValue: Double(currentBasalRate.rate)
                    ),
                    insulinType: self.apsManager.pumpManager?.status.insulinType ?? nil,
                    automatic: true,
                    manuallyEntered: false,
                    isMutable: false
                )
                // Add the new event entry to the result
                insulinDoseEvents.append(newDoseEntry)
            }
        }

        return insulinDoseEvents
    }

    private func getCurrentBasalRate() -> BasalProfileEntry? {
        let now = Date()
        let calendar = Calendar.current

        let basalEntries = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
            ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
            ?? []

        var currentRate: BasalProfileEntry = basalEntries[0]

        for (index, entry) in basalEntries.enumerated() {
            guard let entryTime = TherapySettingsUtil.parseTime(entry.start) else {
                debug(.default, "Invalid entry start time: \(entry.start)")
                continue
            }

            let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
            let entryStartTime = calendar.date(
                bySettingHour: entryComponents.hour!,
                minute: entryComponents.minute!,
                second: entryComponents.second!,
                of: now
            )!

            let entryEndTime: Date
            if index < basalEntries.count - 1,
               let nextEntryTime = TherapySettingsUtil.parseTime(basalEntries[index + 1].start)
            {
                let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                entryEndTime = calendar.date(
                    bySettingHour: nextEntryComponents.hour!,
                    minute: nextEntryComponents.minute!,
                    second: nextEntryComponents.second!,
                    of: now
                )!
            } else {
                entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
            }

            if now >= entryStartTime, now < entryEndTime {
                currentRate = entry
            }
        }

        return currentRate
    }
}

/// Glucose Upload Functionality
extension BaseTidepoolManager {
    func uploadGlucose() async {
        do {
            let glucose = try await glucoseStorage.getGlucoseNotYetUploadedToTidepool()
            uploadGlucose(glucose)

            let manualGlucose = try await glucoseStorage.getManualGlucoseNotYetUploadedToTidepool()
            uploadGlucose(manualGlucose)
        } catch {
            debug(.service, "Error fetching glucose data: \(error)")
        }
    }

    func uploadGlucose(_ glucose: [StoredGlucoseSample]) {
        guard !glucose.isEmpty, let tidepoolService = self.tidepoolService else { return }

        let chunks = glucose.chunks(ofCount: tidepoolService.glucoseDataLimit ?? 100)

        processQueue.async {
            for chunk in chunks {
                tidepoolService.uploadGlucoseData(chunk) { result in
                    switch result {
                    case .success:
                        debug(.nightscout, "Success synchronizing glucose data")

                        // After successful upload, update the isUploadedToTidepool flag in Core Data
                        Task {
                            await self.updateGlucoseAsUploaded(glucose)
                        }
                    case let .failure(error):
                        debug(.nightscout, "Error synchronizing glucose data: \(String(describing: error))")
                    }
                }
            }
        }
    }

    private func updateGlucoseAsUploaded(_ glucose: [StoredGlucoseSample]) async {
        await backgroundContext.perform {
            let ids = glucose.map(\.syncIdentifier) as NSArray
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToTidepool = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToTidepool: \(error.userInfo)"
                )
            }
        }
    }
}

/// Settings Upload Functionality
extension BaseTidepoolManager {
    /// Debounces settings upload requests.
    /// Cancels any pending upload and schedules a new one after the debounce delay.
    /// This prevents redundant uploads when multiple settings observers fire in rapid succession.
    /// All access to `pendingSettingsUpload` is serialized on `processQueue`.
    private func scheduleSettingsUpload() {
        processQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingSettingsUpload?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.uploadSettings()
                }
            }
            self.pendingSettingsUpload = workItem
            self.processQueue.asyncAfter(
                deadline: .now() + Self.settingsUploadDebounceDelay,
                execute: workItem
            )
        }
    }

    func uploadSettings() async {
        guard let tidepoolService = self.tidepoolService as? TidepoolService else {
            return
        }

        // Get CGM device info (lazily resolved to avoid circular dependency)
        let fetchGlucoseManager = resolver?.resolve(FetchGlucoseManager.self)
        let cgmDevice = fetchGlucoseManager?.cgmManager?.cgmManagerStatus.device

        guard let settings = createStoredSettings(cgmDevice: cgmDevice) else {
            return
        }

        processQueue.async {
            tidepoolService.uploadSettingsData([settings]) { result in
                switch result {
                case .success:
                    debug(.service, "Settings uploaded to Tidepool (syncId: \(settings.syncIdentifier))")
                case let .failure(error):
                    debug(.service, "Failed to upload settings to Tidepool: \(error)")
                }
            }
        }
    }
}

// MARK: - Settings Change Observers

extension BaseTidepoolManager: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        // Only trigger upload when therapy-relevant properties change.
        // TrioSettings has ~56 properties, most are UI-only (badges, colors, etc.).
        let closedLoopChanged = lastClosedLoop != settings.closedLoop
        let unitsChanged = lastUnits != settings.units

        lastClosedLoop = settings.closedLoop
        lastUnits = settings.units

        guard closedLoopChanged || unitsChanged else { return }
        scheduleSettingsUpload()
    }
}

extension BaseTidepoolManager: PreferencesObserver {
    func preferencesDidChange(_: Preferences) {
        scheduleSettingsUpload()
    }
}

extension BaseTidepoolManager: StatefulPluggableDelegate {
    func pluginDidUpdateState(_: LoopKit.StatefulPluggable) {}

    func pluginWantsDeletion(_: LoopKit.StatefulPluggable) {
        tidepoolService = nil
    }
}

// MARK: - Settings Conversion

extension BaseTidepoolManager {
    /// Creates a StoredSettings object from current Trio settings
    /// - Parameter cgmDevice: Optional CGM device info (pass from FetchGlucoseManager to avoid circular dependency)
    func createStoredSettings(cgmDevice: HKDevice? = nil) -> StoredSettings? {
        guard let basalProfile: [BasalProfileEntry] = storage
            .retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self),
            let carbRatios: CarbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self),
            let insulinSensitivities: InsulinSensitivities = storage.retrieve(
                OpenAPS.Settings.insulinSensitivities,
                as: InsulinSensitivities.self
            ),
            let bgTargets: BGTargets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
        else {
            debug(.service, "Failed to load Trio therapy settings for Tidepool upload")
            return nil
        }

        let pumpSettings = settingsManager.pumpSettings
        let preferences: Preferences? = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)

        let basalRateSchedule = convertBasalProfile(basalProfile)
        let carbRatioSchedule = convertCarbRatios(carbRatios)
        let insulinSensitivitySchedule = convertInsulinSensitivities(insulinSensitivities)
        let glucoseTargetRangeSchedule = convertBGTargets(bgTargets)

        let pumpDevice = apsManager.pumpManager?.status.device
        let bgUnit: HKUnit = settingsManager.settings.units == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter

        // threshold_setting is always stored in mg/dL; TidepoolServiceKit calls
        // convertTo(unit:) internally, so we pass it through in its native unit
        let suspendThreshold: GlucoseThreshold? = preferences.map { prefs in
            let thresholdValue = Double(prefs.threshold_setting)
            return GlucoseThreshold(unit: .milligramsPerDeciliter, value: thresholdValue)
        }

        return StoredSettings(
            date: Date(),
            controllerTimeZone: TimeZone.current,
            dosingEnabled: settingsManager.settings.closedLoop,
            glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
            preMealTargetRange: nil,
            workoutTargetRange: nil,
            overridePresets: nil,
            scheduleOverride: nil,
            preMealOverride: nil,
            maximumBasalRatePerHour: Double(pumpSettings.maxBasal),
            maximumBolus: Double(pumpSettings.maxBolus),
            suspendThreshold: suspendThreshold,
            insulinType: apsManager.pumpManager?.status.insulinType,
            defaultRapidActingModel: convertInsulinModel(preferences: preferences, pumpSettings: pumpSettings),
            basalRateSchedule: basalRateSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            carbRatioSchedule: carbRatioSchedule,
            notificationSettings: nil,
            controllerDevice: createControllerDevice(),
            cgmDevice: cgmDevice,
            pumpDevice: pumpDevice,
            bloodGlucoseUnit: bgUnit,
            syncIdentifier: contentBasedSyncIdentifier(
                basalProfile: basalProfile,
                carbRatios: carbRatios,
                insulinSensitivities: insulinSensitivities,
                bgTargets: bgTargets,
                pumpSettings: pumpSettings,
                preferences: preferences,
                dosingEnabled: settingsManager.settings.closedLoop
            )
        )
    }

    private func convertBasalProfile(_ entries: [BasalProfileEntry]) -> BasalRateSchedule? {
        let items = entries.map { entry in
            let startTime = TimeInterval(entry.minutes * 60)
            return RepeatingScheduleValue(startTime: startTime, value: Double(entry.rate))
        }
        return BasalRateSchedule(dailyItems: items, timeZone: TimeZone.current)
    }

    private func convertCarbRatios(_ carbRatios: CarbRatios) -> CarbRatioSchedule? {
        let items = carbRatios.schedule.map { entry in
            let startTime = TimeInterval(entry.offset * 60)
            return RepeatingScheduleValue(startTime: startTime, value: Double(entry.ratio))
        }
        return CarbRatioSchedule(unit: .gram(), dailyItems: items, timeZone: TimeZone.current)
    }

    private func convertInsulinSensitivities(_ sensitivities: InsulinSensitivities) -> InsulinSensitivitySchedule? {
        // sensitivities.units comes from the data model itself, not the user's display preference
        let unit: HKUnit = sensitivities.units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter
        let items = sensitivities.sensitivities.map { entry in
            let startTime = TimeInterval(entry.offset * 60)
            return RepeatingScheduleValue(startTime: startTime, value: Double(entry.sensitivity))
        }
        return InsulinSensitivitySchedule(unit: unit, dailyItems: items, timeZone: TimeZone.current)
    }

    private func convertBGTargets(_ bgTargets: BGTargets) -> GlucoseRangeSchedule? {
        // bgTargets.units comes from the data model itself, not the user's display preference
        let unit: HKUnit = bgTargets.units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter
        let items = bgTargets.targets.map { entry in
            let startTime = TimeInterval(entry.offset * 60)
            let minValue = Double(entry.low)
            let maxValue = Double(entry.high)
            return RepeatingScheduleValue(startTime: startTime, value: DoubleRange(minValue: minValue, maxValue: maxValue))
        }
        let schedule = DailyQuantitySchedule(unit: unit, dailyItems: items, timeZone: TimeZone.current)
        return schedule.map { GlucoseRangeSchedule(rangeSchedule: $0) }
    }

    private func convertInsulinModel(preferences: Preferences?, pumpSettings: PumpSettings) -> StoredInsulinModel? {
        guard let curve = preferences?.curve else { return nil }

        let modelType: StoredInsulinModel.ModelType
        let preset: ExponentialInsulinModelPreset
        switch curve {
        case .bilinear,
             .rapidActing:
            modelType = .rapidAdult
            preset = .rapidActingAdult
        case .ultraRapid:
            // Distinguish Fiasp vs Lyumjev using the pump's configured insulin type
            let isLyumjev = apsManager.pumpManager?.status.insulinType == .lyumjev
            modelType = isLyumjev ? .lyumjev : .fiasp
            preset = isLyumjev ? .lyumjev : .fiasp
        }

        let dia = Double(pumpSettings.insulinActionCurve)

        // Use custom peak time if enabled, otherwise fall back to LoopKit preset default
        let peakActivity: TimeInterval
        if let prefs = preferences, prefs.useCustomPeakTime {
            peakActivity = .minutes(Double(prefs.insulinPeakTime))
        } else {
            peakActivity = preset.peakActivity
        }

        return StoredInsulinModel(
            modelType: modelType,
            delay: preset.delay,
            actionDuration: .hours(dia),
            peakActivity: peakActivity
        )
    }

    /// Generates a deterministic UUID based on the content of the therapy settings.
    /// If settings haven't changed, the same UUID is produced, enabling Tidepool
    /// server-side deduplication via the origin ID.
    private func contentBasedSyncIdentifier(
        basalProfile: [BasalProfileEntry],
        carbRatios: CarbRatios,
        insulinSensitivities: InsulinSensitivities,
        bgTargets: BGTargets,
        pumpSettings: PumpSettings,
        preferences: Preferences?,
        dosingEnabled: Bool
    ) -> UUID {
        var hasher = SHA256()

        for entry in basalProfile {
            hasher.update(data: Data("\(entry.minutes):\(entry.rate)".utf8))
        }
        for entry in carbRatios.schedule {
            hasher.update(data: Data("\(entry.offset):\(entry.ratio)".utf8))
        }
        for entry in insulinSensitivities.sensitivities {
            hasher.update(data: Data("\(entry.offset):\(entry.sensitivity)".utf8))
        }
        for entry in bgTargets.targets {
            hasher.update(data: Data("\(entry.offset):\(entry.low):\(entry.high)".utf8))
        }

        hasher.update(data: Data("maxBasal:\(pumpSettings.maxBasal)".utf8))
        hasher.update(data: Data("maxBolus:\(pumpSettings.maxBolus)".utf8))

        if let prefs = preferences {
            hasher.update(data: Data("threshold:\(prefs.threshold_setting)".utf8))
        }

        hasher.update(data: Data("dosingEnabled:\(dosingEnabled)".utf8))

        let digest = hasher.finalize()
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func createControllerDevice() -> StoredSettings.ControllerDevice {
        let device = UIDevice.current
        return StoredSettings.ControllerDevice(
            name: "Trio",
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            model: device.model,
            modelIdentifier: device.getDeviceId
        )
    }
}


// Service extension for rawValue
extension Service {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        [
            "serviceIdentifier": pluginIdentifier,
            "state": rawState
        ]
    }
}
