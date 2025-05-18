import Algorithms
import Combine
import CoreData
import DanaKit
import Foundation
import LoopKit
import LoopKitUI
import MinimedKit
import MockKit
import OmniBLE
import OmniKit
import ShareClient
import SwiftDate
import Swinject
import UserNotifications

protocol DeviceDataManager: GlucoseSource {
    var pumpManager: PumpManagerUI? { get set }
    var bluetoothManager: BluetoothStateManager { get }
    var loopInProgress: Bool { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var recommendsLoop: PassthroughSubject<Void, Never> { get }
    var bolusTrigger: PassthroughSubject<Bool, Never> { get }
    var manualTempBasal: PassthroughSubject<Bool, Never> { get }
    var errorSubject: PassthroughSubject<Error, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }

    func heartbeat(date: Date)
    func createBolusProgressReporter() -> DoseProgressReporter?
    var alertHistoryStorage: AlertHistoryStorage! { get }
}

private let staticPumpManagers: [PumpManagerUI.Type] = [
    MinimedPumpManager.self,
    OmnipodPumpManager.self,
    OmniBLEPumpManager.self,
    DanaKitPumpManager.self,
    MockPumpManager.self
]

private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = [
    MinimedPumpManager.pluginIdentifier: MinimedPumpManager.self,
    OmnipodPumpManager.pluginIdentifier: OmnipodPumpManager.self,
    OmniBLEPumpManager.pluginIdentifier: OmniBLEPumpManager.self,
    DanaKitPumpManager.pluginIdentifier: DanaKitPumpManager.self,
    MockPumpManager.pluginIdentifier: MockPumpManager.self
]

private let accessLock = NSRecursiveLock(label: "BaseDeviceDataManager.accessLock")

final class BaseDeviceDataManager: DeviceDataManager, Injectable {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseDeviceDataManager.processQueue", qos: .userInitiated)
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() var alertHistoryStorage: AlertHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var bluetoothProvider: BluetoothStateManager!

    @Persisted(key: "BaseDeviceDataManager.lastEventDate") var lastEventDate: Date? = nil
    @SyncAccess(lock: accessLock) @Persisted(key: "BaseDeviceDataManager.lastHeartBeatTime") var lastHeartBeatTime: Date =
        .distantPast

    let recommendsLoop = PassthroughSubject<Void, Never>()
    let bolusTrigger = PassthroughSubject<Bool, Never>()
    let errorSubject = PassthroughSubject<Error, Never>()
    let pumpNewStatus = PassthroughSubject<Void, Never>()
    let manualTempBasal = PassthroughSubject<Bool, Never>()

    private let router = TrioApp.resolver.resolve(Router.self)!
    @SyncAccess private var pumpUpdateCancellable: AnyCancellable?
    private var pumpUpdatePromise: Future<Bool, Never>.Promise?
    @SyncAccess var loopInProgress: Bool = false
    private let privateContext = CoreDataStack.shared.newTaskContext()

    var pumpManager: PumpManagerUI? {
        didSet {
            pumpManager?.pumpManagerDelegate = self
            pumpManager?.delegateQueue = processQueue
            rawPumpManager = pumpManager?.rawValue
            UserDefaults.standard.clearLegacyPumpManagerRawValue()
            if let pumpManager = pumpManager {
                pumpDisplayState.value = PumpDisplayState(name: pumpManager.localizedTitle, image: pumpManager.smallImage)
                pumpName.send(pumpManager.localizedTitle)

                var modifiedPreferences = settingsManager.preferences
                let bolusIncrement = Decimal(
                    pumpManager.supportedBolusVolumes.first ??
                        Double(
                            settingsManager.preferences
                                .bolusIncrement
                        )
                )
                modifiedPreferences
                    .bolusIncrement = bolusIncrement != 0.025 ? bolusIncrement : 0.1
                storage.save(modifiedPreferences, as: OpenAPS.Settings.preferences)

                if let omnipod = pumpManager as? OmnipodPumpManager {
                    guard let endTime = omnipod.state.podState?.expiresAt else {
                        pumpExpiresAtDate.send(nil)
                        return
                    }
                    pumpExpiresAtDate.send(endTime)
                }
                if let omnipodBLE = pumpManager as? OmniBLEPumpManager {
                    guard let endTime = omnipodBLE.state.podState?.expiresAt else {
                        pumpExpiresAtDate.send(nil)
                        return
                    }
                    pumpExpiresAtDate.send(endTime)
                }
                if let simulatorPump = pumpManager as? MockPumpManager {
                    pumpDisplayState.value = PumpDisplayState(name: simulatorPump.localizedTitle, image: simulatorPump.smallImage)
                    pumpName.send(simulatorPump.localizedTitle)
                    storage.save(Decimal(simulatorPump.pumpReservoirCapacity), as: OpenAPS.Monitor.reservoir)
                    DispatchQueue.main.async {
                        self.broadcaster.notify(PumpReservoirObserver.self, on: .main) {
                            $0.pumpReservoirDidChange(Decimal(simulatorPump.state.reservoirUnitsRemaining))
                        }
                    }
                    let batteryPercent = Int((simulatorPump.state.pumpBatteryChargeRemaining ?? 1) * 100)
                    let battery = Battery(
                        percent: batteryPercent,
                        voltage: nil,
                        string: batteryPercent >= 10 ? .normal : .low,
                        display: simulatorPump.state.pumpBatteryChargeRemaining != nil
                    )
                    Task {
                        await self.privateContext.perform {
                            let saveBatteryToCoreData = OpenAPS_Battery(context: self.privateContext)
                            saveBatteryToCoreData.id = UUID()
                            saveBatteryToCoreData.date = Date()
                            saveBatteryToCoreData.percent = Double(batteryPercent)
                            saveBatteryToCoreData.voltage = nil
                            saveBatteryToCoreData.status = batteryPercent >= 10 ? BatteryState.normal.rawValue : BatteryState
                                .low.rawValue
                            saveBatteryToCoreData.display = simulatorPump.state.pumpBatteryChargeRemaining != nil

                            do {
                                guard self.privateContext.hasChanges else { return }
                                try self.privateContext.save()
                            } catch {
                                print(error.localizedDescription)
                            }
                        }
                    }
                    DispatchQueue.main.async {
                        self.broadcaster.notify(PumpBatteryObserver.self, on: .main) {
                            $0.pumpBatteryDidChange(battery)
                        }
                    }
                }
            } else {
                pumpDisplayState.value = nil
                pumpExpiresAtDate.send(nil)
                pumpName.send("")
                // Reset bolusIncrement setting to default value, which is 0.1 U
                var modifiedPreferences = settingsManager.preferences
                modifiedPreferences.bolusIncrement = 0.1
                storage.save(modifiedPreferences, as: OpenAPS.Settings.preferences)
                // Remove OpenAPS_Battery entries
                Task {
                    await self.privateContext.perform {
                        let fetchRequest: NSFetchRequest<OpenAPS_Battery> = OpenAPS_Battery.fetchRequest()

                        do {
                            let batteryEntries = try self.privateContext.fetch(fetchRequest)

                            for entry in batteryEntries {
                                self.privateContext.delete(entry)
                            }

                            guard self.privateContext.hasChanges else { return }
                            try self.privateContext.save()

                        } catch {
                            print("Failed to delete OpenAPS_Battery entries: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    @PersistedProperty(key: "PumpManagerState") var rawPumpManager: PumpManager.RawValue?

    var bluetoothManager: BluetoothStateManager { bluetoothProvider }

    var hasBLEHeartbeat: Bool {
        (pumpManager as? MockPumpManager) == nil
    }

    let pumpDisplayState = CurrentValueSubject<PumpDisplayState?, Never>(nil)
    let pumpExpiresAtDate = CurrentValueSubject<Date?, Never>(nil)
    let pumpName = CurrentValueSubject<String, Never>("Pump")

    init(resolver: Resolver) {
        injectServices(resolver)
        setupPumpManager()
        UIDevice.current.isBatteryMonitoringEnabled = true
        broadcaster.register(AlertObserver.self, observer: self)
    }

    func setupPumpManager() {
        if let pumpManagerRawValue = rawPumpManager ?? UserDefaults.standard.legacyPumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
        } else {
            pumpManager = nil
        }
    }

    func createBolusProgressReporter() -> DoseProgressReporter? {
        pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
    }

    func heartbeat(date: Date) {
        guard pumpUpdateCancellable == nil else {
            warning(.deviceManager, "Pump updating already in progress. Skip updating.")
            return
        }

        guard !loopInProgress else {
            warning(.deviceManager, "Loop in progress. Skip updating.")
            return
        }

        func update(_: Future<Bool, Never>.Promise?) {}

        processQueue.safeSync {
            lastHeartBeatTime = date
            updatePumpData()
        }
    }

    private func updatePumpData() {
        guard let pumpManager = pumpManager else {
            debug(.deviceManager, "Pump is not set, skip updating")
            updateUpdateFinished(false)
            return
        }

        debug(.deviceManager, "Start updating the pump data")
        processQueue.safeSync {
            pumpManager.ensureCurrentPumpData { _ in
                debug(.deviceManager, "Pump data updated.")
                self.updateUpdateFinished(true)
            }
        }
    }

    private func updateUpdateFinished(_ recommendsLoop: Bool) {
        pumpUpdateCancellable = nil
        pumpUpdatePromise = nil
        if !recommendsLoop {
            warning(.deviceManager, "Loop recommendation time out or got error. Trying to loop right now.")
        }
        self.recommendsLoop.send()
    }

    private func pumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI? {
        guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
              let Manager = pumpManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? PumpManagerUI
    }

    private func pumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        return staticPumpManagersByIdentifier[managerIdentifier]
    }

    // MARK: - GlucoseSource

    @Persisted(key: "BaseDeviceDataManager.lastFetchGlucoseDate") private var lastFetchGlucoseDate: Date = .distantPast

    var glucoseManager: FetchGlucoseManager?
    var cgmManager: CGMManagerUI?
    var cgmType: CGMType = .enlite

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        guard let medtronic = pumpManager as? MinimedPumpManager else {
            warning(.deviceManager, "Fetch minilink glucose failed: Pump is not Medtronic")
            return Just([]).eraseToAnyPublisher()
        }

        guard lastFetchGlucoseDate.addingTimeInterval(5.minutes.timeInterval) < Date() else {
            return Just([]).eraseToAnyPublisher()
        }

        medtronic.cgmManagerDelegate = self

        return Future<[BloodGlucose], Error> { promise in
            self.processQueue.async {
                medtronic.fetchNewDataIfNeeded { result in
                    switch result {
                    case .noData:
                        debug(.deviceManager, "Minilink glucose is empty")
                        promise(.success([]))
                    case .unreliableData:
                        debug(.deviceManager, "Unreliable data received")
                        promise(.success([]))
                    case let .newData(glucose):
                        let directions: [BloodGlucose.Direction?] = [nil]
                            + glucose.windows(ofCount: 2).map { window -> BloodGlucose.Direction? in
                                let pair = Array(window)
                                guard pair.count == 2 else { return nil }
                                let firstValue = Int(pair[0].quantity.doubleValue(for: .milligramsPerDeciliter))
                                let secondValue = Int(pair[1].quantity.doubleValue(for: .milligramsPerDeciliter))
                                return .init(trend: secondValue - firstValue)
                            }

                        let results = glucose.enumerated().map { index, sample -> BloodGlucose in
                            let value = Int(sample.quantity.doubleValue(for: .milligramsPerDeciliter))
                            return BloodGlucose(
                                _id: sample.syncIdentifier,
                                sgv: value,
                                direction: directions[index],
                                date: Decimal(Int(sample.date.timeIntervalSince1970 * 1000)),
                                dateString: sample.date,
                                unfiltered: Decimal(value),
                                filtered: nil,
                                noise: nil,
                                glucose: value,
                                type: "sgv"
                            )
                        }
                        if let lastDate = results.last?.dateString {
                            self.lastFetchGlucoseDate = lastDate
                        }

                        promise(.success(results))
                    case let .error(error):
                        warning(.deviceManager, "Fetch minilink glucose failed", error: error)
                        promise(.failure(error))
                    }
                }
            }
        }
        .timeout(60 * 3, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }
}

// MARK: - PumpManagerDelegate

extension BaseDeviceDataManager: PumpManagerDelegate {
    var automaticDosingEnabled: Bool {
        settingsManager.settings.closedLoop // Take if close or open loop
    }

    func pumpManager(
        _: LoopKit.PumpManager,
        didRequestBasalRateScheduleChange _: LoopKit.BasalRateSchedule,
        completion _: @escaping (Error?) -> Void
    ) {
        debug(.deviceManager, "pumpManagerBasalRateChange")
    }

    func pumpManagerPumpWasReplaced(_: PumpManager) {
        debug(.deviceManager, "pumpManagerPumpWasReplaced")
    }

    var detectedSystemTimeOffset: TimeInterval {
        // trustedTimeChecker.detectedSystemTimeOffset
        0
    }

    func pumpManager(_: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        debug(.deviceManager, "didAdjustPumpClockBy \(adjustment)")
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        rawPumpManager = pumpManager.rawValue
        if self.pumpManager == nil, let newPumpManager = pumpManager as? PumpManagerUI {
            self.pumpManager = newPumpManager
        }
        pumpName.send(pumpManager.localizedTitle)
    }

    /// heartbeat with pump occurs some issues in the backgroundtask - so never used
    func pumpManagerBLEHeartbeatDidFire(_: PumpManager) {
        debug(.deviceManager, "Pump Heartbeat: do nothing. Pump connection is OK")
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        true
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "New pump status Bolus: \(status.bolusState)")
        debug(.deviceManager, "New pump status Basal: \(String(describing: status.basalDeliveryState))")

        if case .inProgress = status.bolusState {
            bolusTrigger.send(true)
        } else {
            bolusTrigger.send(false)
        }

        if status.insulinType != oldStatus.insulinType {
            settingsManager.updateInsulinCurve(status.insulinType)
        }

        if let omnipod = pumpManager as? OmnipodPumpManager {
            let reservoirVal = omnipod.state.podState?.lastInsulinMeasurements?.reservoirLevel ?? 0xDEAD_BEEF
            // TODO: find the value Pod.maximumReservoirReading
            let reservoir = Decimal(reservoirVal) > 50.0 ? 0xDEAD_BEEF : reservoirVal

            storage.save(Decimal(reservoir), as: OpenAPS.Monitor.reservoir)
            broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
                $0.pumpReservoirDidChange(Decimal(reservoir))
            }

            if let tempBasal = omnipod.state.podState?.unfinalizedTempBasal, !tempBasal.isFinished(),
               !tempBasal.automatic
            {
                // the manual basal temp is launch - block every thing
                debug(.deviceManager, "manual temp basal")
                manualTempBasal.send(true)
            } else {
                // no more manual Temp Basal !
                manualTempBasal.send(false)
            }

            guard let endTime = omnipod.state.podState?.expiresAt else {
                pumpExpiresAtDate.send(nil)
                return
            }
            pumpExpiresAtDate.send(endTime)

            if let startTime = omnipod.state.podState?.activatedAt {
                storage.save(startTime, as: OpenAPS.Monitor.podAge)
            }
        }

        if let omnipodBLE = pumpManager as? OmniBLEPumpManager {
            let reservoirVal = omnipodBLE.state.podState?.lastInsulinMeasurements?.reservoirLevel ?? 0xDEAD_BEEF
            // TODO: find the value Pod.maximumReservoirReading
            let reservoir = Decimal(reservoirVal) > 50.0 ? 0xDEAD_BEEF : reservoirVal

            storage.save(Decimal(reservoir), as: OpenAPS.Monitor.reservoir)
            broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
                $0.pumpReservoirDidChange(Decimal(reservoir))
            }

            // manual temp basal on
            if let tempBasal = omnipodBLE.state.podState?.unfinalizedTempBasal, !tempBasal.isFinished(),
               !tempBasal.automatic
            {
                // the manual basal temp is launch - block every thing
                debug(.deviceManager, "manual temp basal")
                manualTempBasal.send(true)
            } else {
                // no more manual Temp Basal !
                manualTempBasal.send(false)
            }

            guard let endTime = omnipodBLE.state.podState?.expiresAt else {
                pumpExpiresAtDate.send(nil)
                return
            }
            pumpExpiresAtDate.send(endTime)

            if let startTime = omnipodBLE.state.podState?.activatedAt {
                storage.save(startTime, as: OpenAPS.Monitor.podAge)
            }
        }

        if let simulatorPump = pumpManager as? MockPumpManager {
            broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
                $0.pumpReservoirDidChange(Decimal(simulatorPump.state.reservoirUnitsRemaining))
            }
        }
    }

    func pumpManagerWillDeactivate(_: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        pumpManager = nil
        broadcaster.notify(PumpDeactivatedObserver.self, on: processQueue) {
            $0.pumpDeactivatedDidChange()
        }
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "error: \(error), reason: \(String(describing: error.failureReason))")
        errorSubject.send(error)
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation _: Date?,
        replacePendingEvents _: Bool,
        completion: @escaping (_ error: Error?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))

        Task {
            do {
                // filter buggy TBRs > maxBasal from MDT
                let events = events.filter {
                    // type is optional...
                    guard let type = $0.type, type == .tempBasal else { return true }
                    return $0.dose?.unitsPerHour ?? 0 <= Double(settingsManager.pumpSettings.maxBasal)
                }
                debug(.deviceManager, "Storing \(events.count) new pump events: \(events)")
                try await pumpHistoryStorage.storePumpEvents(events)
                lastEventDate = events.last?.date
                completion(nil)
            } catch {
                debug(.deviceManager, "\(DebuggingIdentifiers.failed) Failed to store pump events: \(error)")
            }
        }
    }

    func pumpManager(
        _: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Reservoir Value \(units), at: \(date)")
        storage.save(Decimal(units), as: OpenAPS.Monitor.reservoir)
        broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
            $0.pumpReservoirDidChange(Decimal(units))
        }

        completion(.success((
            newValue: Reservoir(startDate: Date(), unitVolume: units),
            lastValue: nil,
            areStoredValuesContinuous: true
        )))
    }

    func pumpManagerRecommendsLoop(_: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Pump recommends loop")
        guard let promise = pumpUpdatePromise else {
            warning(.deviceManager, "We do not waiting for loop recommendation at this time.")
            return
        }
        promise(.success(true))
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        lastEventDate?.addingTimeInterval(-15.minutes.timeInterval) ?? Date().addingTimeInterval(-2.hours.timeInterval)
    }
}

// MARK: - DeviceManagerDelegate

extension BaseDeviceDataManager: DeviceManagerDelegate {
    func issueAlert(_ alert: Alert) {
        alertHistoryStorage.storeAlert(
            AlertEntry(
                alertIdentifier: alert.identifier.alertIdentifier,
                primitiveInterruptionLevel: alert.interruptionLevel.storedValue as? Decimal,
                issuedDate: Date(),
                managerIdentifier: alert.identifier.managerIdentifier,
                triggerType: alert.trigger.storedType,
                triggerInterval: alert.trigger.storedInterval as? Decimal,
                contentTitle: alert.foregroundContent?.title,
                contentBody: alert.foregroundContent?.body
            )
        )
    }

    func retractAlert(identifier: Alert.Identifier) {
        alertHistoryStorage.deleteAlert(identifier: identifier.alertIdentifier)
    }

    func doesIssuedAlertExist(identifier _: Alert.Identifier, completion _: @escaping (Result<Bool, Error>) -> Void) {
        debug(.deviceManager, "doesIssueAlertExist")
    }

    func lookupAllUnretracted(managerIdentifier _: String, completion _: @escaping (Result<[PersistedAlert], Error>) -> Void) {
        debug(.deviceManager, "lookupAllUnretracted")
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[PersistedAlert], Error>) -> Void
    ) {}

    func recordRetractedAlert(_: Alert, at _: Date) {}

    func removeNotificationRequests(for _: DeviceManager, identifiers: [String]) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: DeviceLogEntryType,
        message: String,
        completion _: ((Error?) -> Void)?
    ) {
        debug(.deviceManager, "Device message: \(message)")
    }
}

// MARK: - CGMManagerDelegate

extension BaseDeviceDataManager: CGMManagerDelegate {
    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        glucoseStorage.syncDate().addingTimeInterval(-10.minutes.timeInterval) // additional time to calculate directions
    }

    func cgmManager(_: CGMManager, hasNew _: CGMReadingResult) {}

    func cgmManager(_: LoopKit.CGMManager, hasNew _: [LoopKit.PersistedCgmEvent]) {}

    func cgmManagerWantsDeletion(_: CGMManager) {}

    func cgmManagerDidUpdateState(_: CGMManager) {}

    func credentialStoragePrefix(for _: CGMManager) -> String { "BaseDeviceDataManager" }

    func cgmManager(_: CGMManager, didUpdate _: CGMManagerStatus) {}
}

// MARK: - AlertPresenter

extension BaseDeviceDataManager: AlertObserver {
    func AlertDidUpdate(_ alerts: [AlertEntry]) {
        alerts.forEach { alert in
            if alert.acknowledgedDate == nil {
                ackAlert(alert: alert)
            }
        }
    }

    private func ackAlert(alert: AlertEntry) {
        let alertIssueDate = alert.issuedDate

        processQueue.async {
            // if not alert in OmniPod/BLE, the acknowledgeAlert didn't do callbacks- Hack to manage this case
            if let omnipodBLE = self.pumpManager as? OmniBLEPumpManager {
                if omnipodBLE.state.activeAlerts.isEmpty {
                    // force to ack alert in the alertStorage
                    self.alertHistoryStorage.ackAlert(alertIssueDate, nil)
                }
            }

            if let omniPod = self.pumpManager as? OmnipodPumpManager {
                if omniPod.state.activeAlerts.isEmpty {
                    // force to ack alert in the alertStorage
                    self.alertHistoryStorage.ackAlert(alertIssueDate, nil)
                }
            }

            self.pumpManager?.acknowledgeAlert(alertIdentifier: alert.alertIdentifier) { error in
                if let error = error {
                    self.alertHistoryStorage.ackAlert(alertIssueDate, error.localizedDescription)
                    debug(.deviceManager, "acknowledge not succeeded with error \(error)")
                } else {
                    self.alertHistoryStorage.ackAlert(alertIssueDate, nil)
                }
            }

            self.broadcaster.notify(pumpNotificationObserver.self, on: self.processQueue) {
                $0.pumpNotification(alert: alert)
            }
        }
    }
}

// extension BaseDeviceDataManager: AlertPresenter {
//    func issueAlert(_: Alert) {}
//    func retractAlert(identifier _: Alert.Identifier) {}
// }

// MARK: Others

protocol PumpReservoirObserver {
    func pumpReservoirDidChange(_ reservoir: Decimal)
}

protocol PumpBatteryObserver {
    func pumpBatteryDidChange(_ battery: Battery)
}

protocol PumpDeactivatedObserver {
    func pumpDeactivatedDidChange()
}
