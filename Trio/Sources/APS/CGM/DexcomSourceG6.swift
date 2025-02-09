import CGMBLEKit
import Combine
import Foundation
import LoopKit
import LoopKitUI
import ShareClient

final class DexcomSourceG6: GlucoseSource {
    private let processQueue = DispatchQueue(label: "DexcomSource.processQueue")
    private let glucoseStorage: GlucoseStorage!
    var glucoseManager: FetchGlucoseManager?

    var cgmManager: CGMManagerUI?
    var cgmType: CGMType = .dexcomG6

    var cgmHasValidSensorSession: Bool = false

    private var promise: Future<[BloodGlucose], Error>.Promise?

    init(glucoseStorage: GlucoseStorage, glucoseManager: FetchGlucoseManager) {
        self.glucoseStorage = glucoseStorage
        self.glucoseManager = glucoseManager
        cgmManager = G6CGMManager
            .init(state: TransmitterManagerState(
                transmitterID: UserDefaults.standard
                    .dexcomTransmitterID ?? "000000",
                shouldSyncToRemoteService: glucoseManager.settingsManager.settings.uploadGlucose
            ))
        cgmManager?.delegateQueue = processQueue
        cgmManager?.cgmManagerDelegate = self
    }

    var transmitterID: String {
        guard let cgmG6Manager = cgmManager as? G6CGMManager else { return "000000" }
        return cgmG6Manager.transmitter.ID
    }

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60 * 5, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { _ in
            self.processQueue.async {
                guard let cgmManager = self.cgmManager else { return }
                cgmManager.fetchNewDataIfNeeded { result in
                    self.processCGMReadingResult(cgmManager, readingResult: result) {
                        // nothing to do
                    }
                }
            }
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    deinit {
        // dexcomManager.transmitter.stopScanning()
    }
}

extension DexcomSourceG6: CGMManagerDelegate {
    func deviceManager(
        _: LoopKit.DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type _: LoopKit.DeviceLogEntryType,
        message: String,
        completion _: ((Error?) -> Void)?
    ) {
        debug(.deviceManager, "device Manager for \(String(describing: deviceIdentifier)) : \(message)")
    }

    func issueAlert(_: LoopKit.Alert) {}

    func retractAlert(identifier _: LoopKit.Alert.Identifier) {}

    func doesIssuedAlertExist(identifier _: LoopKit.Alert.Identifier, completion _: @escaping (Result<Bool, Error>) -> Void) {}

    func lookupAllUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void
    ) {}

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void
    ) {}

    func recordRetractedAlert(_: LoopKit.Alert, at _: Date) {}

    func cgmManagerWantsDeletion(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, " CGM Manager with identifier \(manager.managerIdentifier) wants deletion")
        glucoseManager?.cgmGlucoseSourceType = nil
    }

    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        processCGMReadingResult(manager, readingResult: readingResult) {
            debug(.deviceManager, "DEXCOM - Direct return done")
        }
    }

    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return glucoseStorage.lastGlucoseDate()
        //  return glucoseStore.latestGlucose?.startDate
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        guard let g6Manager = manager as? TransmitterManager else {
            return
        }
        glucoseManager?.settingsManager.settings.uploadGlucose = g6Manager.shouldSyncToRemoteService
        UserDefaults.standard.dexcomTransmitterID = g6Manager.rawState["transmitterID"] as? String
    }

    func credentialStoragePrefix(for _: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        UUID().uuidString
    }

    func cgmManager(_: CGMManager, didUpdate status: CGMManagerStatus) {
        processQueue.async {
            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
        }
    }

    private func processCGMReadingResult(
        _: CGMManager,
        readingResult: CGMReadingResult,
        completion: @escaping () -> Void
    ) {
        debug(.deviceManager, "DEXCOM - Process CGM Reading Result launched with \(readingResult)")
        switch readingResult {
        case let .newData(values):
            if let cgmG6Manager = cgmManager as? G6CGMManager,
               let activationDate = cgmG6Manager.latestReading?.activationDate,
               let sessionStartDate = cgmG6Manager.latestReading?.sessionStartDate
            {
                let bloodGlucose = values.compactMap { newGlucoseSample -> BloodGlucose? in
                    let quantity = newGlucoseSample.quantity
                    let value = Int(quantity.doubleValue(for: .milligramsPerDeciliter))
                    return BloodGlucose(
                        _id: UUID().uuidString,
                        sgv: value,
                        direction: .init(trendType: newGlucoseSample.trend),
                        date: Decimal(Int(newGlucoseSample.date.timeIntervalSince1970 * 1000)),
                        dateString: newGlucoseSample.date,
                        unfiltered: Decimal(value),
                        filtered: nil,
                        noise: nil,
                        glucose: value,
                        type: "sgv",
                        activationDate: activationDate,
                        sessionStartDate: sessionStartDate,
                        transmitterID: self.transmitterID
                    )
                }
                promise?(.success(bloodGlucose))
                completion()
            } else {
                // Handle the case where activationDate or sessionStartDate is nil
                completion()
            }
        case .unreliableData:
            // loopManager.receivedUnreliableCGMReading()
            promise?(.failure(GlucoseDataError.unreliableData))
            completion()
        case .noData:
            promise?(.failure(GlucoseDataError.noData))
            completion()
        case let .error(error):
            promise?(.failure(error))
            completion()
        }
    }
}

extension DexcomSourceG6 {
    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Dexcom tramsmitter ID: \(transmitterID)"]
    }
}
