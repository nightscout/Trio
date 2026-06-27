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
        fetchIfNeeded()
            .filter { !$0.isEmpty }
            .first()
            .timeout(60 * 5, scheduler: processQueue, options: nil, customError: nil)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            guard let self = self else { return }
            self.processQueue.async {
                guard let cgmManager = self.cgmManager else { return }
                cgmManager.fetchNewDataIfNeeded { _ in
                    // Ignore values returned from fetchNewDataIfNeeded since
                    // these come from share client and cause a race condition
                    // that causes the promise to complete before a CGM value
                    // has a chance to return. From looking at the code this should
                    // only impact G6 since that is the only CGM manager that will
                    // return data and only if share credentials are set
                    promise(.success([]))
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

    /// Forwards CGMManager-issued alerts into the unified `TrioAlertManager`
    /// pipeline so they get the same in-app banner + UN scheduling + history
    /// logging treatment as everything else. Used to be a no-op; on
    /// dev-libre3 / LibreLoop builds that meant CGM-issued alerts (sensor
    /// failure, signal loss, expiry, etc.) silently dropped.
    func issueAlert(_ alert: LoopKit.Alert) {
        glucoseManager?.trioAlertManager?.issueAlert(alert)
    }

    func retractAlert(identifier: LoopKit.Alert.Identifier) {
        glucoseManager?.trioAlertManager?.retractAlert(identifier: identifier)
    }

    /// LoopKit asks this on reconnect to avoid re-issuing an alert that's
    /// still live. `TrioAlertManager` deduplicates downstream via its own
    /// throttler and live-alert table, so answering "no" here is safe — at
    /// worst we get one duplicate banner, which the throttler suppresses.
    func doesIssuedAlertExist(identifier _: LoopKit.Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false))
    }

    func lookupAllUnretracted(
        managerIdentifier _: String,
        completion: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void
    ) {
        completion(.success([]))
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void
    ) {
        completion(.success([]))
    }

    /// LoopKit calls this when a manager itself decides an alert is no
    /// longer relevant. Mirror the action on our pipeline so the in-app
    /// banner, scheduled UN, and history all clear.
    func recordRetractedAlert(_ alert: LoopKit.Alert, at _: Date) {
        glucoseManager?.trioAlertManager?.retractAlert(identifier: alert.identifier)
    }

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

            switch self.readCGMResult(readingResult: readingResult) {
            case let .success(glucose):
                self.glucoseManager?.newGlucoseFromCgmManager(newGlucose: glucose)
            case .failure:
                debug(.deviceManager, "CGM PLUGIN - unable to read CGM result")
            }

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
        dispatchPrecondition(condition: .onQueue(processQueue))

        return glucoseStorage.lastGlucoseDate()
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
                    id: UUID().uuidString,
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
