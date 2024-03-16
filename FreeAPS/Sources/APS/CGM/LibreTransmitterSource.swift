import Combine
import Foundation
import LibreTransmitter
import LibreTransmitterUI
import LoopKit
import LoopKitUI
import Swinject

// protocol LibreTransmitterSource: GlucoseSource {
//    var manager: LibreTransmitterManager? { get set }
// }

final class LibreTransmitterSource: GlucoseSource {
    private let processQueue = DispatchQueue(label: "BaseLibreTransmitterSource.processQueue")
    private var glucoseStorage: GlucoseStorage!
    var glucoseManager: FetchGlucoseManager?

    var cgmManager: CGMManagerUI?
    var cgmType: CGMType = .libreTransmitter

    var cgmHasValidSensorSession: Bool = false

    // @Injected() var glucoseStorage: GlucoseStorage!
//    @Injected() var calibrationService: CalibrationService!

    private var promise: Future<[BloodGlucose], Error>.Promise?

//    @Persisted(key: "LibreTransmitterManager.configured") private(set) var configured = false

    init(glucoseStorage: GlucoseStorage, glucoseManager: FetchGlucoseManager) {
        self.glucoseStorage = glucoseStorage
        self.glucoseManager = glucoseManager
        cgmManager = LibreTransmitterManagerV3()
        cgmManager?.cgmManagerDelegate = self
        cgmManager?.delegateQueue = processQueue
    }

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
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

//    func sourceInfo() -> [String: Any]? {
//        if let battery = manager?.battery {
//            return ["transmitterBattery": battery]
//        }
//        return nil
//    }
}

extension LibreTransmitterSource: CGMManagerDelegate {
    private func processCGMReadingResult(
        _: CGMManager,
        readingResult: CGMReadingResult,
        completion: @escaping () -> Void
    ) {
        switch readingResult {
        case let .newData(values):
            if let libreManager = cgmManager as? LibreTransmitterManagerV3 {
                let glucose = values.compactMap { newGlucoseSample -> BloodGlucose in
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
                        activationDate: libreManager.sensorInfoObservable.activatedAt,
                        sessionStartDate: libreManager.sensorInfoObservable.activatedAt,
                        transmitterID: libreManager.sensorInfoObservable.sensorSerial
                    )
                }
                NSLog("Debug Libre \(glucose)")
                promise?(.success(glucose))
                completion()
            }

        case .unreliableData:
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

    func cgmManager(_ manager: LoopKit.CGMManager, hasNew readingResult: LoopKit.CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        processCGMReadingResult(manager, readingResult: readingResult) {
            debug(.deviceManager, "Libre transmitter - Direct return done")
        }
    }

    func cgmManagerDidUpdateState(_: LoopKit.CGMManager) {
        // TODO: if useful in regard of configuration
    }

    func cgmManager(_: LoopKit.CGMManager, didUpdate status: LoopKit.CGMManagerStatus) {
        DispatchQueue.main.async {
            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
        }
    }

    func startDateToFilterNewData(for _: LoopKit.CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return glucoseStorage.lastGlucoseDate()
    }

    func cgmManager(_: LoopKit.CGMManager, hasNew events: [LoopKit.PersistedCgmEvent]) {
        // TODO: Events in APS ?
        // currently only display in log the date of the event
        events.forEach { debug(.deviceManager, "events from CGM at \($0.date)") }
    }

    func cgmManagerWantsDeletion(_ manager: LoopKit.CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, " CGM Manager with identifier \(manager.pluginIdentifier) wants deletion")
        glucoseManager?.cgmGlucoseSourceType = nil
    }

    func credentialStoragePrefix(for _: LoopKit.CGMManager) -> String {
        UUID().uuidString
    }

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
}
