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
    func uploadGlucose(device: HKDevice?) async
    func forceTidepoolDataUpload(device: HKDevice?)
}

final class BaseTidepoolManager: TidepoolManager, Injectable, CarbsStoredDelegate, PumpHistoryDelegate {
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var pluginManager: PluginManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!

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

    @PersistedProperty(key: "TidepoolState") var rawTidepoolManager: Service.RawValue?

    init(resolver: Resolver) {
        injectServices(resolver)
        loadTidepoolManager()
        pumpHistoryStorage.delegate = self
        carbsStorage.delegate = self
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

    private func subscribe() {
        broadcaster.register(TempTargetsObserver.self, observer: self)
    }

    func sourceInfo() -> [String: Any]? {
        nil
    }

    func uploadCarbs() async {
        uploadCarbs(await carbsStorage.getCarbsNotYetUploadedToHealth())
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
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToHealth: \(error.userInfo)"
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

        let eventsBasal = events.filter { $0.type == .tempBasal || $0.type == .tempBasalDuration }
            .sorted { $0.timestamp < $1.timestamp }

//        let doseDataBasal: [DoseEntry] = eventsBasal.reduce([]) { result, event in
//            var result = result
//            switch event.type {
//            case .tempBasal:
//                // update the previous tempBasal with endtime = starttime of the last event
//                if let last: DoseEntry = result.popLast() {
//                    let value = max(
//                        0,
//                        Double(event.timestamp.timeIntervalSince1970 - last.startDate.timeIntervalSince1970) / 3600
//                    ) *
//                        (last.scheduledBasalRate?.doubleValue(for: .internationalUnitsPerHour) ?? 0.0)
//                    result.append(DoseEntry(
//                        type: .tempBasal,
//                        startDate: last.startDate,
//                        endDate: event.timestamp,
//                        value: value,
//                        unit: last.unit,
//                        deliveredUnits: value,
//                        syncIdentifier: last.syncIdentifier,
//                        insulinType: last.insulinType,
//                        automatic: last.automatic,
//                        manuallyEntered: last.manuallyEntered
//                    ))
//                }
//                result.append(DoseEntry(
//                    type: .tempBasal,
//                    startDate: event.timestamp,
//                    value: 0.0,
//                    unit: .units,
//                    syncIdentifier: event.id,
//                    scheduledBasalRate: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: Double(event.amount!)),
//                    insulinType: nil,
//                    automatic: true,
//                    manuallyEntered: false,
//                    isMutable: true
//                ))
//            case .tempBasalDuration:
//                if let last: DoseEntry = result.popLast(),
//                   last.type == .tempBasal,
//                   last.startDate == event.timestamp
//                {
//                    let durationMin = event.durationMin ?? 0
//                    // result.append(last)
//                    let value = (Double(durationMin) / 60.0) *
//                        (last.scheduledBasalRate?.doubleValue(for: .internationalUnitsPerHour) ?? 0.0)
//                    result.append(DoseEntry(
//                        type: .tempBasal,
//                        startDate: last.startDate,
//                        endDate: Calendar.current.date(byAdding: .minute, value: durationMin, to: last.startDate) ?? last
//                            .startDate,
//                        value: value,
//                        unit: last.unit,
//                        deliveredUnits: value,
//                        syncIdentifier: last.syncIdentifier,
//                        scheduledBasalRate: last.scheduledBasalRate,
//                        insulinType: last.insulinType,
//                        automatic: last.automatic,
//                        manuallyEntered: last.manuallyEntered
//                    ))
//                }
//            default: break
//            }
//            return result
//        }

        let tempBasals: [DoseEntry] = events.compactMap { event -> DoseEntry? in
            switch event.type {
            case .tempBasal:
                return DoseEntry(
                    type: .tempBasal,
                    startDate: event.timestamp,
                    endDate: event.timestamp
                        .addingTimeInterval(TimeInterval(minutes: Double(event.duration ?? 0))),
                    value: 0.0,
                    unit: .units,
                    syncIdentifier: event.id,
                    scheduledBasalRate: HKQuantity(
                        unit: .internationalUnitsPerHour,
                        doubleValue: Double(event.rate!)
                    ),
                    insulinType: nil,
                    automatic: true,
                    manuallyEntered: false,
                    isMutable: true
                )
            default: return nil
            }
        }

        let boluses: [DoseEntry] = events.compactMap { event -> DoseEntry? in
            switch event.type {
            case .bolus:
                return DoseEntry(
                    type: .bolus,
                    startDate: event.timestamp,
                    endDate: event.timestamp,
                    value: Double(event.amount!),
                    unit: .units,
                    deliveredUnits: nil,
                    syncIdentifier: event.id,
                    scheduledBasalRate: nil,
                    insulinType: nil,
                    automatic: event.isSMB ?? true,
                    manuallyEntered: event.isExternal ?? false
                )
            default: return nil
            }
        }

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
            tidepoolService.uploadDoseData(created: tempBasals + boluses, deleted: []) { result in
                switch result {
                case let .failure(error):
                    debug(.nightscout, "Error synchronizing Dose data: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing Dose data")
                    // After successful upload, update the isUploadedToTidepool flag in Core Data
                    Task {
                        let insulinEvents = events
                            .filter {
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
                        let pumpEventType = events.map({ $0.type.mapEventTypeToPumpEventType()
                        })
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
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToHealth: \(error.userInfo)"
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

    func uploadGlucose(device: HKDevice?) async {
        // TODO: get correct glucose values
        let glucose: [BloodGlucose] = await glucoseStorage.getGlucoseNotYetUploadedToNightscout()

        guard !glucose.isEmpty, let tidepoolService = self.tidepoolService else { return }

        let glucoseWithoutCorrectID = glucose.filter { UUID(uuidString: $0._id ?? UUID().uuidString) != nil }

        let chunks = glucoseWithoutCorrectID.chunks(ofCount: tidepoolService.glucoseDataLimit ?? 100)

        processQueue.async {
            for chunk in chunks {
                // Link all glucose values with the current device
                let chunkStoreGlucose = chunk.map { $0.convertStoredGlucoseSample(device: device) }

                tidepoolService.uploadGlucoseData(chunkStoreGlucose) { result in
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

    private func updateGlucoseAsUploaded(_ glucose: [BloodGlucose]) async {
        await backgroundContext.perform {
            let ids = glucose.map(\.id) as NSArray
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
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToHealth: \(error.userInfo)"
                )
            }
        }
    }

    /// force to uploads all data in Tidepool Service
    func forceTidepoolDataUpload(device: HKDevice?) {
        Task {
            await uploadInsulin()
            await uploadCarbs()
            await uploadGlucose(device: device)
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
