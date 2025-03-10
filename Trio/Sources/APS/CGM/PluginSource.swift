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
        debug(.deviceManager, "PluginSource: fetch() called - combining BLE fetch and fetchIfNeeded")

        // Check if CGM manager is available
        if cgmManager == nil {
            debug(.deviceManager, "PluginSource: fetch() - No CGM manager available, returning empty array immediately")
            return Just([]).eraseToAnyPublisher()
        }

        // Create a publisher that will emit a timeout event after 2 minutes
        let timeoutPublisher = Just(())
            .delay(for: .seconds(120), scheduler: processQueue)
            .map { _ -> [BloodGlucose] in
                debug(.deviceManager, "PluginSource: fetch() - Global timeout reached, returning empty array")
                return []
            }
            .eraseToAnyPublisher()

        // Combine the BLE fetch, fetchIfNeeded, and timeout publishers
        return Publishers.Merge3(
            callBLEFetch()
                .handleEvents(receiveOutput: { values in
                    if !values.isEmpty {
                        debug(.deviceManager, "PluginSource: fetch() - callBLEFetch returned \(values.count) values")
                    }
                }),
            fetchIfNeeded()
                .handleEvents(receiveOutput: { values in
                    if !values.isEmpty {
                        debug(.deviceManager, "PluginSource: fetch() - fetchIfNeeded returned \(values.count) values")
                    }
                }),
            timeoutPublisher
        )
        .filter { values in
            let isEmpty = values.isEmpty
            debug(.deviceManager, "PluginSource: filter - received \(values.count) values, isEmpty: \(isEmpty)")
            return !isEmpty
        }
        .first()
        .handleEvents(
            receiveSubscription: { _ in debug(.deviceManager, "PluginSource: fetch publisher received subscription") },
            receiveOutput: { values in
                debug(.deviceManager, "PluginSource: fetch publisher emitting \(values.count) values") },
            receiveCompletion: { completion in
                if case .finished = completion {
                    debug(.deviceManager, "PluginSource: fetch publisher completed normally")
                } else {
                    debug(.deviceManager, "PluginSource: fetch publisher completed with error or cancellation")
                }
            },
            receiveCancel: { debug(.deviceManager, "PluginSource: fetch publisher was cancelled") }
        )
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func callBLEFetch() -> AnyPublisher<[BloodGlucose], Never> {
        debug(.deviceManager, "PluginSource: callBLEFetch() called")
        return Future<[BloodGlucose], Error> { [weak self] promise in
            guard let self = self else {
                debug(.deviceManager, "PluginSource: callBLEFetch - self is nil, returning empty array")
                promise(.success([]))
                return
            }

            debug(.deviceManager, "PluginSource: callBLEFetch - storing promise for future resolution")

            // If there's already a promise, resolve it with an empty array to avoid memory leaks
            if self.promise != nil {
                debug(.deviceManager, "PluginSource: callBLEFetch - found existing promise, resolving it with empty array")
                self.promise?(.success([]))
            }

            // Store the new promise
            self.promise = promise

            // Create a timeout work item
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }

                // Check if we still have a promise (it hasn't been fulfilled yet)
                if self.promise != nil {
                    debug(.deviceManager, "PluginSource: callBLEFetch - timeout reached, resolving promise with empty array")
                    self.promise?(.success([]))
                    self.promise = nil
                }
            }

            // Schedule the timeout
            self.processQueue.asyncAfter(deadline: .now() + 60, execute: timeoutWorkItem)
        }
        .handleEvents(
            receiveSubscription: { _ in debug(.deviceManager, "PluginSource: callBLEFetch received subscription") },
            receiveOutput: { values in
                debug(.deviceManager, "PluginSource: callBLEFetch received output with \(values.count) values") },
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    debug(.deviceManager, "PluginSource: callBLEFetch completed with error: \(error.localizedDescription)")
                } else {
                    debug(.deviceManager, "PluginSource: callBLEFetch completed successfully")
                }
            }
        )
        .timeout(60 * 5, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        debug(.deviceManager, "PluginSource: fetchIfNeeded() called")
        return Future<[BloodGlucose], Error> { [weak self] promise in
            guard let self = self else {
                debug(.deviceManager, "PluginSource: fetchIfNeeded - self is nil, returning empty array")
                promise(.success([]))
                return
            }
            debug(.deviceManager, "PluginSource: fetchIfNeeded - about to dispatch to processQueue")
            self.processQueue.async {
                guard let cgmManager = self.cgmManager else {
                    debug(.deviceManager, "PluginSource: fetchIfNeeded - cgmManager is nil, returning empty array")
                    promise(.success([]))
                    return
                }

                // Log CGM manager details
                debug(.deviceManager, "PluginSource: fetchIfNeeded - using CGM manager of type: \(type(of: cgmManager))")
                debug(.deviceManager, "PluginSource: fetchIfNeeded - CGM manager identifier: \(cgmManager.pluginIdentifier)")
                debug(
                    .deviceManager,
                    "PluginSource: fetchIfNeeded - CGM manager has valid sensor session: \(self.cgmHasValidSensorSession)"
                )

                // Set a timeout to ensure the promise is resolved
                let timeoutWorkItem = DispatchWorkItem {
                    debug(.deviceManager, "PluginSource: fetchIfNeeded - TIMEOUT reached, resolving promise with empty array")
                    promise(.success([]))
                }
                self.processQueue.asyncAfter(deadline: .now() + 30, execute: timeoutWorkItem)

                debug(.deviceManager, "PluginSource: fetchIfNeeded - calling fetchNewDataIfNeeded on cgmManager")

                do {
                    // Check if we have a valid sensor session
                    if !self.cgmHasValidSensorSession {
                        debug(
                            .deviceManager,
                            "PluginSource: fetchIfNeeded - WARNING: CGM does not have a valid sensor session"
                        )
                    }

                    debug(.deviceManager, "PluginSource: fetchIfNeeded - about to call fetchNewDataIfNeeded")
                    cgmManager.fetchNewDataIfNeeded { result in
                        // Cancel the timeout since we got a response
                        timeoutWorkItem.cancel()

                        debug(
                            .deviceManager,
                            "PluginSource: fetchIfNeeded - received callback from fetchNewDataIfNeeded with result: \(result)"
                        )
                        let processedResult = self.readCGMResult(readingResult: result)
                        if case let .success(values) = processedResult {
                            debug(
                                .deviceManager,
                                "PluginSource: fetchIfNeeded - processed result contains \(values.count) values"
                            )
                            if !values.isEmpty, !values.isEmpty {
                                let firstValue = values.first!
                                debug(
                                    .deviceManager,
                                    "PluginSource: fetchIfNeeded - first glucose value: \(firstValue.glucose ?? 0) mg/dL at \(firstValue.dateString)"
                                )
                            } else {
                                debug(.deviceManager, "PluginSource: fetchIfNeeded - processed result contains no values")
                            }
                        } else if case let .failure(error) = processedResult {
                            debug(
                                .deviceManager,
                                "PluginSource: fetchIfNeeded - processed result contains error: \(error.localizedDescription)"
                            )
                        }
                        promise(processedResult)
                    }
                } catch {
                    // Cancel the timeout since we're resolving the promise now
                    timeoutWorkItem.cancel()

                    debug(
                        .deviceManager,
                        "PluginSource: fetchIfNeeded - exception thrown when calling fetchNewDataIfNeeded: \(error.localizedDescription)"
                    )
                    promise(.failure(error))
                }
            }
        }
        .handleEvents(
            receiveSubscription: { _ in debug(.deviceManager, "PluginSource: fetchIfNeeded received subscription") },
            receiveOutput: { values in
                debug(.deviceManager, "PluginSource: fetchIfNeeded received output with \(values.count) values") },
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    debug(.deviceManager, "PluginSource: fetchIfNeeded completed with error: \(error.localizedDescription)")
                } else {
                    debug(.deviceManager, "PluginSource: fetchIfNeeded completed successfully")
                }
            }
        )
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
            self.glucoseManager?.deleteGlucoseSource()
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
