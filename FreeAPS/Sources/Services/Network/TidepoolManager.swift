import Combine
import CoreData
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import Swinject

protocol TidepoolManager {
    func addTidepoolService(service: Service)
    func getTidepoolServiceUI() -> ServiceUI?
    func getTidepoolPluginHost() -> PluginHost?
    func uploadCarbs() async
    func deleteCarbs(withSyncId id: UUID, carbs: Decimal, at: Date, enteredBy: String)
    func uploadInsulin() async
    func deleteInsulin(withSyncId id: String, amount: Decimal, at: Date)
    func uploadGlucose() async
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

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")
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

    private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    @PersistedProperty(key: "TidepoolState") var rawTidepoolManager: Service.RawValue?

    init(resolver: Resolver) {
        injectServices(resolver)
        loadTidepoolManager()

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: DispatchQueue.global(qos: .background))
                .share()
                .eraseToAnyPublisher()

        registerHandlers()

        subscribe()
    }

    /// load the Tidepool Remote Data Service if available
    fileprivate func loadTidepoolManager() {
        if let rawTidepoolManager = rawTidepoolManager {
            tidepoolService = tidepoolServiceFromRaw(rawTidepoolManager)
            tidepoolService?.serviceDelegate = self
            tidepoolService?.stateDelegate = self
        }
    }

    /// allows access to tidepoolService as a simple ServiceUI
    func getTidepoolServiceUI() -> ServiceUI? {
        if let tidepoolService = self.tidepoolService {
            return tidepoolService as! any ServiceUI as ServiceUI
        } else {
            return nil
        }
    }

    /// get the pluginHost of Tidepool
    func getTidepoolPluginHost() -> PluginHost? {
        self as PluginHost
    }

    func addTidepoolService(service: Service) {
        tidepoolService = service as! any RemoteDataService as RemoteDataService
    }

    /// load the Tidepool Remote Data Service from raw storage
    private func tidepoolServiceFromRaw(_ rawValue: [String: Any]) -> RemoteDataService? {
        guard let rawState = rawValue["state"] as? Service.RawStateValue,
              let serviceType = pluginManager.getServiceTypeByIdentifier("TidepoolService")
        else {
            return nil
        }
        if let service = serviceType.init(rawState: rawState) {
            return service as! any RemoteDataService as RemoteDataService
        } else { return nil }
    }

    private func registerHandlers() {
        coreDataPublisher?.filterByEntityName("PumpEventStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.uploadInsulin()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("CarbEntryStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.uploadCarbs()
            }
        }.store(in: &subscriptions)

        // TODO: this is currently done in FetchGlucoseManager and forced there inside a background task.
        // leave it there, or move it here? not sure…
//        coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
//            guard let self = self else { return }
//            Task { [weak self] in
//                guard let self = self else { return }
//                await self.uploadGlucose(device: fetchCgmManager.cgmManager?.cgmManagerStatus.device)
//            }
//        }.store(in: &subscriptions)33
    }

    private func subscribe() {
        broadcaster.register(TempTargetsObserver.self, observer: self)
    }

    func sourceInfo() -> [String: Any]? {
        nil
    }

    func uploadCarbs() async {
        uploadCarbs(await carbsStorage.getCarbsNotYetUploadedToTidepool())
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
                        debug(.nightscout, "Error synchronizing carbs data: \(String(describing: error))")
                    case .success:
                        debug(.nightscout, "Success synchronizing carbs data")
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
                    debug(.nightscout, "Error synchronizing carbs data: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing carbs data.")
                }
            }
        }
    }

    func uploadInsulin() async {
        uploadDose(await pumpHistoryStorage.getPumpHistoryNotYetUploadedToTidepool())
    }

    func uploadDose(_ events: [PumpHistoryEvent]) {
        guard !events.isEmpty, let tidepoolService = self.tidepoolService else { return }

        let tempBasalEventCount = events.filter { $0.type == .tempBasal }.count

        // Fetch existing entries with an additional +1 count to get the previous entry as well -> need to update
        var existingTempBasalEntries: [PumpEventStored] = CoreDataStack.shared.fetchEntities(
            ofType: PumpEventStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: false,
            fetchLimit: tempBasalEventCount + 1,
            batchSize: 50
        ).filter { $0.tempBasal != nil }

        // remove first fetched existing entry, so new events and old events are off by 1 index, so the same index is always current event in events and the previous event to that one in existing events array.
        if existingTempBasalEntries.isNotEmpty, existingTempBasalEntries.count > 1 {
            existingTempBasalEntries.removeFirst()
        }

        let insulinDoseEvents: [DoseEntry] = events.reduce([]) { result, event in
            var result = result
            switch event.type {
            case .tempBasal:
                if let duration = event.duration, let amount = event.amount, let currentBasalRate = self.getCurrentBasalRate() {
                    let value = (Decimal(duration) / 60.0) * amount

                    // Create updated previous entry, if applicable -> update end date
                    if let lastEntry = existingTempBasalEntries.first, let lastTimeStamp = lastEntry.timestamp {
                        let lastEndDate = event.timestamp
                        let lastDuration = lastEndDate.timeIntervalSince(lastTimeStamp) / 3600
                        let lastDeliveredUnits = Double(lastDuration / 60.0) *
                            Double(truncating: lastEntry.tempBasal?.rate ?? 0.0)

                        let updatedLastEntry = DoseEntry(
                            type: .tempBasal,
                            startDate: lastTimeStamp,
                            endDate: lastEndDate,
                            value: lastDeliveredUnits,
                            unit: .units,
                            deliveredUnits: lastDeliveredUnits,
                            syncIdentifier: lastEntry.id ?? UUID().uuidString,
                            insulinType: apsManager.pumpManager?.status.insulinType ?? nil,
                            automatic: true,
                            manuallyEntered: false,
                            isMutable: false
                        )
                        result.append(updatedLastEntry)
                    }

                    // Create new entry for current event
                    let newDoseEntry = DoseEntry(
                        type: .tempBasal,
                        startDate: event.timestamp,
                        endDate: event.timestamp.addingTimeInterval(TimeInterval(minutes: Double(duration))),
                        value: Double(value),
                        unit: .units,
                        deliveredUnits: Double(value),
                        syncIdentifier: event.id,
                        scheduledBasalRate: HKQuantity(
                            unit: .internationalUnitsPerHour,
                            doubleValue: Double(currentBasalRate.rate)
                        ),
                        insulinType: apsManager.pumpManager?.status.insulinType ?? nil,
                        automatic: true,
                        manuallyEntered: false,
                        isMutable: false
                    )

                    result.append(newDoseEntry)

                    // Remove the first element from existingTempBasalEntries so that it does not get processed again
                    if existingTempBasalEntries.isNotEmpty {
                        existingTempBasalEntries.removeFirst()
                    }
                }

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
                    insulinType: apsManager.pumpManager?.status.insulinType ?? nil,
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

        processQueue.async {
            tidepoolService.uploadDoseData(created: insulinDoseEvents, deleted: []) { result in
                switch result {
                case let .failure(error):
                    debug(.nightscout, "Error synchronizing Dose data: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing Dose data")
                    // After successful upload, update the isUploadedToTidepool flag in Core Data
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
                    debug(.nightscout, "Error synchronizing Pump Event data: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing Pump Event data")
                    // After successful upload, update the isUploadedToTidepool flag in Core Data
                    Task {
                        let pumpEventType = events.map { $0.type.mapEventTypeToPumpEventType() }
                        let pumpEvents = events.filter { _ in pumpEventType.contains(pumpEventType) }

                        await self.updateInsulinAsUploaded(pumpEvents)
                    }
                }
            }
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

    func uploadGlucose() async {
        uploadGlucose(await glucoseStorage.getGlucoseNotYetUploadedToTidepool())
        uploadGlucose(
            await glucoseStorage
                .getManualGlucoseNotYetUploadedToTidepool()
        )
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

    /// force to uploads all data in Tidepool Service
    func forceTidepoolDataUpload() {
        Task {
            await uploadInsulin()
            await uploadCarbs()
            await uploadGlucose()
        }
    }
}

extension BaseTidepoolManager: TempTargetsObserver {
    func tempTargetsDidUpdate(_: [TempTarget]) {}
}

extension BaseTidepoolManager: ServiceDelegate {
    var hostIdentifier: String {
        // TODO: shouldn't this rather be `org.nightscout.Trio` ?
        "com.loopkit.Loop" // To check
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

extension BaseTidepoolManager {
    private func getCurrentBasalRate() -> BasalProfileEntry? {
        let now = Date()
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        dateFormatter.timeZone = TimeZone.current

        let basalEntries = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
            ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
            ?? []

        var currentRate: BasalProfileEntry = basalEntries[0]

        for (index, entry) in basalEntries.enumerated() {
            guard let entryTime = dateFormatter.date(from: entry.start) else {
                print("Invalid entry start time: \(entry.start)")
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
               let nextEntryTime = dateFormatter.date(from: basalEntries[index + 1].start)
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

extension BaseTidepoolManager: StatefulPluggableDelegate {
    func pluginDidUpdateState(_: LoopKit.StatefulPluggable) {}

    func pluginWantsDeletion(_: LoopKit.StatefulPluggable) {
        tidepoolService = nil
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
