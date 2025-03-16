import CGMBLEKit
import Combine
import Foundation
import G7SensorKit
import LibreTransmitter
import LoopKit
import LoopKitUI

final class PluginSource: GlucoseSource {
    private let processQueue = DispatchQueue(label: "CGMPluginSource.processQueue")
    private let glucoseStorage: GlucoseStorage!
    var glucoseManager: FetchGlucoseManager?

    var cgmManager: CGMManagerUI?

    var cgmHasValidSensorSession: Bool = false

    private var promise: Future<[BloodGlucose], Error>.Promise?

    init(glucoseStorage: GlucoseStorage, glucoseManager: FetchGlucoseManager) {
        self.glucoseStorage = glucoseStorage
        self.glucoseManager = glucoseManager

        cgmManager = glucoseManager.cgmManager
        cgmManager?.delegateQueue = processQueue
        cgmManager?.cgmManagerDelegate = self
    }

    /// Function that fetches blood glucose data
    /// This function combines two data fetching mechanisms (`callBLEFetch` and `fetchIfNeeded`) into a single publisher.
    /// It returns the first non-empty result from either of the sources within a 5-minute timeout period.
    /// If no valid data is fetched within the timeout, it returns an empty array.
    ///
    /// - Parameter timer: An optional `DispatchTimer` (not used in the function but can be used to trigger fetch logic).
    /// - Returns: An `AnyPublisher` that emits an array of `BloodGlucose` values or an empty array if an error occurs or the timeout is reached.
    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Publishers.Merge(
            callBLEFetch(),
            fetchIfNeeded()
        )
        .filter { !$0.isEmpty }
        .first()
        .timeout(60 * 5, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func callBLEFetch() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60 * 5, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            guard let self = self else { return }
            self.processQueue.async {
                guard let cgmManager = self.cgmManager else { return }
                cgmManager.fetchNewDataIfNeeded { result in
                    promise(self.readCGMResult(readingResult: result))
                }
            }
        }
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    deinit {
        // dexcomManager.transmitter.stopScanning()
    }
}

extension PluginSource: CGMManagerDelegate {
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
        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            debug(.deviceManager, " CGM Manager with identifier \(manager.pluginIdentifier) wants deletion")
            Task {
                await self.glucoseManager?.deleteGlucoseSource()
            }
        }
    }

    func cgmManager(_: CGMManager, hasNew readingResult: CGMReadingResult) {
        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            self.promise?(self.readCGMResult(readingResult: readingResult))
            debug(.deviceManager, "CGM PLUGIN - Direct return done")
        }
    }

    func cgmManager(_: LoopKit.CGMManager, hasNew events: [LoopKit.PersistedCgmEvent]) {
        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            // TODO: Events in APS ?
            // currently only display in log the date of the event
            events.forEach { event in
                debug(.deviceManager, "events from CGM at \(event.date)")

                if event.type == .sensorStart {
                    self.glucoseManager?.removeCalibrations()
                }
            }
        }
    }

    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        var date: Date?

        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            date = glucoseStorage.lastGlucoseDate()
        }

        return date
    }

    func cgmManagerDidUpdateState(_ cgmManager: CGMManager) {
        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            guard let fetchGlucoseManager = self.glucoseManager else {
                debug(
                    .deviceManager,
                    "Could not gracefully unwrap FetchGlucoseManager upon observing LoopKit's cgmManagerDidUpdateState"
                )
                return
            }
            // Adjust app-specific NS Upload setting value when CGM setting is changed
            fetchGlucoseManager.settingsManager.settings.uploadGlucose = cgmManager.shouldSyncToRemoteService

            fetchGlucoseManager.updateGlucoseSource(
                cgmGlucoseSourceType: fetchGlucoseManager.settingsManager.settings.cgm,
                cgmGlucosePluginId: fetchGlucoseManager.settingsManager.settings.cgmPluginIdentifier,
                newManager: cgmManager as? CGMManagerUI
            )
        }
    }

    func credentialStoragePrefix(for _: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        UUID().uuidString
    }

    func cgmManager(_: CGMManager, didUpdate status: CGMManagerStatus) {
        debug(.deviceManager, "CGM Manager did update state to \(status)")

        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
        }
    }

    private func readCGMResult(readingResult: CGMReadingResult) -> Result<[BloodGlucose], Error> {
        debug(.deviceManager, "PLUGIN CGM - Process CGM Reading Result launched with \(readingResult)")

        if glucoseManager?.glucoseSource == nil {
            debug(
                .deviceManager,
                "No glucose source available."
            )
        }

        switch readingResult {
        case let .newData(values):

            var sensorActivatedAt: Date?
            var sensorStartDate: Date?
            var sensorTransmitterID: String?

            /// SAGE
            if let cgmTransmitterManager = cgmManager as? LibreTransmitterManagerV3 {
                let sensorInfo = cgmTransmitterManager.sensorInfoObservable
                sensorActivatedAt = sensorInfo.activatedAt
                sensorStartDate = sensorInfo.activatedAt
                sensorTransmitterID = sensorInfo.sensorSerial
            } else if let cgmTransmitterManager = cgmManager as? G5CGMManager {
                let latestReading = cgmTransmitterManager.latestReading
                sensorActivatedAt = latestReading?.activationDate
                sensorStartDate = latestReading?.sessionStartDate
                sensorTransmitterID = latestReading?.transmitterID
            } else if let cgmTransmitterManager = cgmManager as? G6CGMManager {
                let latestReading = cgmTransmitterManager.latestReading
                sensorActivatedAt = latestReading?.activationDate
                sensorStartDate = latestReading?.sessionStartDate
                sensorTransmitterID = latestReading?.transmitterID
            } else if let cgmTransmitterManager = cgmManager as? G7CGMManager {
                sensorActivatedAt = cgmTransmitterManager.sensorActivatedAt
                sensorStartDate = cgmTransmitterManager.sensorActivatedAt
                sensorTransmitterID = cgmTransmitterManager.sensorName
            }

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
                    activationDate: sensorActivatedAt,
                    sessionStartDate: sensorStartDate,
                    transmitterID: sensorTransmitterID
                )
            }
            return .success(bloodGlucose)
        case .unreliableData:
            // loopManager.receivedUnreliableCGMReading()
            return .failure(GlucoseDataError.unreliableData)
        case .noData:
            return .failure(GlucoseDataError.noData)
        case let .error(error):
            return .failure(error)
        }
    }
}

extension PluginSource {
    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Plugin CGM source"]
    }
}
