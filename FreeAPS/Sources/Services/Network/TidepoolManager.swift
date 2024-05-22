import Combine
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import Swinject

protocol TidepoolManager {
    func addTidepoolService(service: Service)
    func getTidepoolServiceUI() -> ServiceUI?
    func getTidepoolPluginHost() -> PluginHost?
    func deleteCarbs(at date: Date, isFPU: Bool?, fpuID: String?, syncID: String)
    func deleteInsulin(at date: Date)
//    func uploadStatus()
    func uploadGlucose(device: HKDevice?)
    func forceUploadData(device: HKDevice?)
//    func uploadPreferences(_ preferences: Preferences)
//    func uploadProfileAndSettings(_: Bool)
}

final class BaseTidepoolManager: TidepoolManager, Injectable {
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

    @PersistedProperty(key: "TidepoolState") var rawTidepoolManager: Service.RawValue?

    init(resolver: Resolver) {
        injectServices(resolver)
        loadTidepoolManager()
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
        broadcaster.register(PumpHistoryObserver.self, observer: self)
        broadcaster.register(CarbsObserver.self, observer: self)
        broadcaster.register(TempTargetsObserver.self, observer: self)
    }

    func sourceInfo() -> [String: Any]? {
        nil
    }

    func uploadCarbs() {
        let carbs: [CarbsEntry] = carbsStorage.recent()

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
                        debug(.nightscout, "Success synchronizing carbs data:")
                    }
                }
            }
        }
    }

    func deleteCarbs(at date: Date, isFPU: Bool?, fpuID: String?, syncID _: String) {
        guard let tidepoolService = self.tidepoolService else { return }

        processQueue.async {
            var carbsToDelete: [CarbsEntry] = []
            let allValues = self.storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self) ?? []

            if let isFPU = isFPU, isFPU {
                guard let fpuID = fpuID else { return }
                carbsToDelete = allValues.filter { $0.fpuID == fpuID }.removeDublicates()
            } else {
                carbsToDelete = allValues.filter { $0.createdAt == date }.removeDublicates()
            }

            let syncCarb = carbsToDelete.map { d in
                d.convertSyncCarb(operation: .delete)
            }

            tidepoolService.uploadCarbData(created: [], updated: [], deleted: syncCarb) { result in
                switch result {
                case let .failure(error):
                    debug(.nightscout, "Error synchronizing carbs data: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing carbs data:")
                }
            }
        }
    }

    func deleteInsulin(at d: Date) {
        let allValues = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) ?? []

        guard !allValues.isEmpty, let tidepoolService = self.tidepoolService else { return }

        var doseDataToDelete: [DoseEntry] = []

        guard let entry = allValues.first(where: { $0.timestamp == d }) else {
            return
        }
        doseDataToDelete
            .append(DoseEntry(
                type: .bolus,
                startDate: entry.timestamp,
                value: Double(entry.amount!),
                unit: .units,
                syncIdentifier: entry.id
            ))

        processQueue.async {
            tidepoolService.uploadDoseData(created: [], deleted: doseDataToDelete) { result in
                switch result {
                case let .failure(error):
                    debug(.nightscout, "Error synchronizing Dose delete data: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing Dose delete data:")
                }
            }
        }
    }

    func uploadDose() {
        let events = pumpHistoryStorage.recent()
        guard !events.isEmpty, let tidepoolService = self.tidepoolService else { return }

        let eventsBasal = events.filter { $0.type == .tempBasal || $0.type == .tempBasalDuration }
            .sorted { $0.timestamp < $1.timestamp }

        let doseDataBasal: [DoseEntry] = eventsBasal.reduce([]) { result, event in
            var result = result
            switch event.type {
            case .tempBasal:
                // update the previous tempBasal with endtime = starttime of the last event
                if let last: DoseEntry = result.popLast() {
                    let value = max(
                        0,
                        Double(event.timestamp.timeIntervalSince1970 - last.startDate.timeIntervalSince1970) / 3600
                    ) *
                        (last.scheduledBasalRate?.doubleValue(for: .internationalUnitsPerHour) ?? 0.0)
                    result.append(DoseEntry(
                        type: .tempBasal,
                        startDate: last.startDate,
                        endDate: event.timestamp,
                        value: value,
                        unit: last.unit,
                        deliveredUnits: value,
                        syncIdentifier: last.syncIdentifier,
                        // scheduledBasalRate: last.scheduledBasalRate,
                        insulinType: last.insulinType,
                        automatic: last.automatic,
                        manuallyEntered: last.manuallyEntered
                    ))
                }
                result.append(DoseEntry(
                    type: .tempBasal,
                    startDate: event.timestamp,
                    value: 0.0,
                    unit: .units,
                    syncIdentifier: event.id,
                    scheduledBasalRate: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: Double(event.rate!)),
                    insulinType: nil,
                    automatic: true,
                    manuallyEntered: false,
                    isMutable: true
                ))
            case .tempBasalDuration:
                if let last: DoseEntry = result.popLast(),
                   last.type == .tempBasal,
                   last.startDate == event.timestamp
                {
                    let durationMin = event.durationMin ?? 0
                    // result.append(last)
                    let value = (Double(durationMin) / 60.0) *
                        (last.scheduledBasalRate?.doubleValue(for: .internationalUnitsPerHour) ?? 0.0)
                    result.append(DoseEntry(
                        type: .tempBasal,
                        startDate: last.startDate,
                        endDate: Calendar.current.date(byAdding: .minute, value: durationMin, to: last.startDate) ?? last
                            .startDate,
                        value: value,
                        unit: last.unit,
                        deliveredUnits: value,
                        syncIdentifier: last.syncIdentifier,
                        scheduledBasalRate: last.scheduledBasalRate,
                        insulinType: last.insulinType,
                        automatic: last.automatic,
                        manuallyEntered: last.manuallyEntered
                    ))
                }
            default: break
            }
            return result
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
                    automatic: true,
                    manuallyEntered: false
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
            tidepoolService.uploadDoseData(created: doseDataBasal + boluses, deleted: []) { result in
                switch result {
                case let .failure(error):
                    debug(.nightscout, "Error synchronizing Dose data: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing Dose data:")
                }
            }

            tidepoolService.uploadPumpEventData(pumpEvents) { result in
                switch result {
                case let .failure(error):
                    debug(.nightscout, "Error synchronizing Pump Event data: \(String(describing: error))")
                case .success:
                    debug(.nightscout, "Success synchronizing Pump Event data:")
                }
            }
        }
    }

    func uploadGlucose(device: HKDevice?) {
        let glucose: [BloodGlucose] = glucoseStorage.recent()

        guard !glucose.isEmpty, let tidepoolService = self.tidepoolService else { return }

        let glucoseWithoutCorrectID = glucose.filter { UUID(uuidString: $0._id) != nil }

        processQueue.async {
            glucoseWithoutCorrectID.chunks(ofCount: tidepoolService.glucoseDataLimit ?? 100)
                .forEach { chunk in
                    // all glucose attached with the current device ;-(

                    let chunkStoreGlucose = Array(chunk).map {
                        $0.convertStoredGlucoseSample(device: device)
                    }
                    tidepoolService.uploadGlucoseData(chunkStoreGlucose) { result in
                        switch result {
                        case let .failure(error):
                            debug(.nightscout, "Error synchronizing glucose data: \(String(describing: error))")
                        // self.uploadFailed(key)
                        case .success:
                            debug(.nightscout, "Success synchronizing glucose data:")
                        }
                    }
                }
        }
    }

    /// force to uploads all data in Tidepool Service
    func forceUploadData(device: HKDevice?) {
        uploadDose()
        uploadCarbs()
        uploadGlucose(device: device)
    }
}

extension BaseTidepoolManager: PumpHistoryObserver {
    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        uploadDose()
    }
}

extension BaseTidepoolManager: CarbsObserver {
    func carbsDidUpdate(_: [CarbsEntry]) {
        uploadCarbs()
    }
}

extension BaseTidepoolManager: TempTargetsObserver {
    func tempTargetsDidUpdate(_: [TempTarget]) {}
}

extension BaseTidepoolManager: ServiceDelegate {
    var hostIdentifier: String {
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
