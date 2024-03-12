//
//  TransmitterManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import ShareClient
import os.log

public protocol TransmitterManagerObserver: AnyObject {
    func transmitterManagerDidUpdateLatestReading(_ manager: TransmitterManager)
}


public class TransmitterManager: TransmitterDelegate {

    var state: TransmitterManagerState {
        get {
            return lockedState.value
        }
    }
    private func setState(_ changes: (_ state: inout TransmitterManagerState) -> Void) -> Void {
        return setStateWithResult(changes)
    }

    @discardableResult
    private func mutateState(_ changes: (_ state: inout TransmitterManagerState) -> Void) -> TransmitterManagerState {
        return setStateWithResult({ (state) -> TransmitterManagerState in
            changes(&state)
            return state
        })
    }

    private func setStateWithResult<ReturnType>(_ changes: (_ state: inout TransmitterManagerState) -> ReturnType) -> ReturnType {
        var oldValue: TransmitterManagerState!
        var returnType: ReturnType!
        let newValue = lockedState.mutate { (state) in
            oldValue = state
            returnType = changes(&state)
        }

        if oldValue != newValue {
            self.stateDidUpdate()
        }

        return returnType
    }

    func stateDidUpdate() {
        // to be implemented in subclass
    }

    private let lockedState: Locked<TransmitterManagerState>

    private let observers = WeakSynchronizedSet<TransmitterManagerObserver>()


    public var hasValidSensorSession: Bool {
        // TODO: we should decode and persist transmitter session state
        return !state.transmitterID.isEmpty
    }
    
    public var cgmManagerStatus: CGMManagerStatus {
        return CGMManagerStatus(hasValidSensorSession: hasValidSensorSession, device: device)
    }

    public required init(state: TransmitterManagerState) {
        self.lockedState = Locked(state)
        self.transmitter = Transmitter(id: state.transmitterID, activationDate: state.transmitterStartDate, passiveModeEnabled: state.passiveModeEnabled)
        self.shareManager = ShareClientManager()

        self.transmitter.delegate = self
        
        #if targetEnvironment(simulator)
        setupSimulatedSampleGenerator()
        #endif

    }
    
    #if targetEnvironment(simulator)
    var simulatedSampleGeneratorTimer: DispatchSourceTimer?

    private func setupSimulatedSampleGenerator() {

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.loopkit.simulatedSampleGenerator"))
        timer.schedule(deadline: .now() + .seconds(10), repeating: .minutes(5))
        timer.setEventHandler(handler: { [weak self] in
            self?.generateSimulatedSample()
        })
        self.simulatedSampleGeneratorTimer = timer
        timer.resume()
    }

    private func generateSimulatedSample() {
        let timestamp = Date()
        let syncIdentifier =  "\(self.state.transmitterID) \(timestamp)"
        let period = TimeInterval(hours: 3)
        func glucoseValueFunc(timestamp: Date, period: Double) -> Double {
            return 100 + 20 * cos(timestamp.timeIntervalSinceReferenceDate.remainder(dividingBy: period) / period * Double.pi * 2)
        }
        let glucoseValue = glucoseValueFunc(timestamp: timestamp, period: period)
        let prevGlucoseValue = glucoseValueFunc(timestamp: timestamp - period, period: period)
        let trendRateValue = glucoseValue - prevGlucoseValue
        let trend: GlucoseTrend? = {
            switch trendRateValue {
            case -0.01...0.01:
                return .flat
            case -2 ..< -0.01:
                return .down
            case -5 ..< -2:
                return .downDown
            case -Double.greatestFiniteMagnitude ..< -5:
                return .downDownDown
            case 0.01...2:
                return .up
            case 2...5:
                return .upUp
            case 5...Double.greatestFiniteMagnitude:
                return .upUpUp
            default:
                return nil
            }
        }()

        let quantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: glucoseValue)
        let trendRate = HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: trendRateValue)
        let sample = NewGlucoseSample(date: timestamp, quantity: quantity, condition: nil, trend: trend, trendRate: trendRate, isDisplayOnly: false, wasUserEntered: false, syncIdentifier: syncIdentifier)
        self.updateDelegate(with: .newData([sample]))
    }
    #endif

    required convenience public init?(rawState: CGMManager.RawStateValue) {
        guard let state = TransmitterManagerState(rawValue: rawState) else {
            return nil
        }

        self.init(state: state)
    }

    public var rawState: CGMManager.RawStateValue {
        return state.rawValue
    }
    
    func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
    }

    public var shouldSyncToRemoteService: Bool {
        get {
            return state.shouldSyncToRemoteService
        }
        set {
            self.mutateState { state in
                state.shouldSyncToRemoteService = newValue
            }
        }
    }

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            return shareManager.cgmManagerDelegate
        }
        set {
            shareManager.cgmManagerDelegate = newValue
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            return shareManager.delegateQueue
        }
        set {
            shareManager.delegateQueue = newValue
        }
    }

    private(set) public var latestConnection: Date? {
        get {
            return lockedLatestConnection.value
        }
        set {
            lockedLatestConnection.value = newValue
        }
    }
    private let lockedLatestConnection: Locked<Date?> = Locked(nil)

    public let shareManager: ShareClientManager

    public let transmitter: Transmitter
    let log = OSLog(category: "TransmitterManager")

    public var providesBLEHeartbeat: Bool {
        return dataIsFresh
    }

    public var glucoseDisplay: GlucoseDisplayable? {
        let transmitterDate = latestReading?.readDate ?? .distantPast
        let shareDate = shareManager.latestBackfill?.startDate ?? .distantPast

        if transmitterDate >= shareDate {
            return latestReading
        } else {
            return shareManager.glucoseDisplay
        }
    }

    public var managedDataInterval: TimeInterval? {
        if transmitter.passiveModeEnabled {
            return .hours(3)
        }

        return shareManager.managedDataInterval
    }

    private(set) public var latestReading: Glucose? {
        get {
            return lockedLatestReading.value
        }
        set {
            lockedLatestReading.value = newValue
        }
    }
    private let lockedLatestReading: Locked<Glucose?> = Locked(nil)

    private var dataIsFresh: Bool {
        guard let latestGlucose = latestReading,
            latestGlucose.readDate > Date(timeIntervalSinceNow: .minutes(-4.5)) else {
            return false
        }

        return true
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        // Ensure our transmitter connection is active
        transmitter.resumeScanning()

        // If our last glucose was less than 4.5 minutes ago, don't fetch.
        guard !dataIsFresh else {
            completion(.noData)
            return
        }
        
        if let latestReading = latestReading {
            log.default("Fetching new glucose from Share because last reading is %{public}.1f minutes old", latestReading.readDate.timeIntervalSinceNow.minutes)
        } else {
            log.default("Fetching new glucose from Share because we don't have a previous reading")
        }

        shareManager.fetchNewDataIfNeeded(completion)
    }

    public var device: HKDevice? {
        return nil
    }

    public var debugDescription: String {
        return [
            "## \(String(describing: type(of: self)))",
            "latestReading: \(String(describing: latestReading))",
            "latestConnection: \(String(describing: latestConnection))",
            "dataIsFresh: \(dataIsFresh)",
            "providesBLEHeartbeat: \(providesBLEHeartbeat)",
            shareManager.debugDescription,
            "observers.count: \(observers.cleanupDeallocatedElements().count)",
            String(reflecting: transmitter),
        ].joined(separator: "\n")
    }

    private func updateDelegate(with result: CGMReadingResult) {
        if let manager = self as? CGMManager {
            shareManager.delegate.notify { (delegate) in
                delegate?.cgmManager(manager, hasNew: result)
            }
        }

        notifyObserversOfLatestReading()
    }
    
    private func notifyDelegateOfStateChange() {
        if let manager = self as? CGMManager {
            shareManager.delegate.notify { (delegate) in
                delegate?.cgmManagerDidUpdateState(manager)
            }
        }
    }


    // MARK: - TransmitterDelegate

    public func transmitterDidConnect(_ transmitter: Transmitter) {
        log.default("%{public}@", #function)
        latestConnection = Date()
        logDeviceCommunication("Connected", type: .connection)
    }

    public func transmitter(_ transmitter: Transmitter, didError error: Error) {
        log.error("%{public}@: %{public}@", #function, String(describing: error))
        updateDelegate(with: .error(error))
        logDeviceCommunication("Error: \(error)", type: .error)
    }

    public func transmitter(_ transmitter: Transmitter, didRead glucose: Glucose) {
        guard glucose != latestReading else {
            updateDelegate(with: .noData)
            return
        }

        var events: [PersistedCgmEvent] = []

        if state.transmitterStartDate == nil {
            mutateState { state in
                state.transmitterStartDate = glucose.activationDate
            }
            events.append(PersistedCgmEvent(
                date: glucose.activationDate,
                type: .transmitterStart,
                deviceIdentifier: transmitter.ID,
                expectedLifetime: .hours(24 * 90)
            ))
        }

        if state.sensorStartOffset != glucose.timeMessage.sessionStartTime {
            mutateState { state in
                state.sensorStartOffset = glucose.timeMessage.sessionStartTime
            }
            events.append(PersistedCgmEvent(
                date: glucose.sessionStartDate,
                type: .sensorStart,
                deviceIdentifier: transmitter.ID,
                expectedLifetime: .hours(24 * 10),
                warmupPeriod: .hours(2)
            ))
        }

        if !events.isEmpty {
            shareManager.delegate.notify { delegate in
                delegate?.cgmManager(self.shareManager, hasNew: events)
            }
        }

        latestReading = glucose

        logDeviceCommunication("New reading: \(glucose.readDate)", type: .receive)

        guard glucose.state.hasReliableGlucose else {
            log.default("%{public}@: Unreliable glucose: %{public}@", #function, String(describing: glucose.state))
            updateDelegate(with: .error(CalibrationError.unreliableState(glucose.state)))
            return
        }
        
        guard let quantity = glucose.glucose else {
            updateDelegate(with: .noData)
            return
        }

        log.default("%{public}@: New glucose", #function)

        updateDelegate(with: .newData([
            NewGlucoseSample(
                date: glucose.readDate,
                quantity: quantity,
                condition: glucose.condition,
                trend: glucose.trendType,
                trendRate: glucose.trendRate,
                isDisplayOnly: glucose.isDisplayOnly,
                wasUserEntered: glucose.isDisplayOnly,
                syncIdentifier: glucose.syncIdentifier,
                device: device
            )
        ]))
    }

    public func transmitter(_ transmitter: Transmitter, didReadBackfill glucose: [Glucose]) {
        let samples = glucose.compactMap { (glucose) -> NewGlucoseSample? in
            guard glucose != latestReading, glucose.state.hasReliableGlucose, let quantity = glucose.glucose else {
                return nil
            }

            return NewGlucoseSample(
                date: glucose.readDate,
                quantity: quantity,
                condition: glucose.condition,
                trend: glucose.trendType,
                trendRate: glucose.trendRate,
                isDisplayOnly: glucose.isDisplayOnly,
                wasUserEntered: glucose.isDisplayOnly,
                syncIdentifier: glucose.syncIdentifier,
                device: device
            )
        }

        guard samples.count > 0 else {
            return
        }

        updateDelegate(with: .newData(samples))

        logDeviceCommunication("New backfill: \(String(describing: samples.first?.date))", type: .receive)
    }

    public func transmitter(_ transmitter: Transmitter, didReadUnknownData data: Data) {
        log.error("Unknown sensor data: %{public}@", data.hexadecimalString)
        // This can be used for protocol discovery, but isn't necessary for normal operation

        logDeviceCommunication("Unknown sensor data: \(data.hexadecimalString)", type: .error)
    }
}


// MARK: - Observer management
extension TransmitterManager {
    public func addObserver(_ observer: TransmitterManagerObserver, queue: DispatchQueue) {
        observers.insert(observer, queue: queue)
    }

    public func removeObserver(_ observer: TransmitterManagerObserver) {
        observers.removeElement(observer)
    }

    private func notifyObserversOfLatestReading() {
        observers.forEach { (observer) in
            observer.transmitterManagerDidUpdateLatestReading(self)
        }
    }
}


public class G5CGMManager: TransmitterManager, CGMManager {
    public static let pluginIdentifier: String = "DexG5Transmitter"

    public let localizedTitle = LocalizedString("Dexcom G5", comment: "CGM display title")

    public let isOnboarded = true   // No distinction between created and onboarded

    public var appURL: URL? {
        return URL(string: "dexcomcgm://")
    }

    public override var device: HKDevice? {
        return HKDevice(
            name: transmitter.ID,
            manufacturer: "Dexcom",
            model: "G5 Mobile",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: String(CGMBLEKitVersionNumber),
            localIdentifier: nil,
            udiDeviceIdentifier: "00386270000002"
        )
    }
    
    override func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
        self.cgmManagerDelegate?.deviceManager(self, logEventForDeviceIdentifier: transmitter.ID, type: type, message: message, completion: nil)
    }

    override func stateDidUpdate() {
        shareManager.delegate.notify { delegate in
            delegate?.cgmManagerDidUpdateState(self)
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
        }
    }
}


public class G6CGMManager: TransmitterManager, CGMManager {
    public static let pluginIdentifier: String = "DexG6Transmitter"

    public let localizedTitle = LocalizedString("Dexcom G6", comment: "CGM display title")

    public let isOnboarded = true   // No distinction between created and onboarded

    public var appURL: URL? {
        return nil
    }

    public override var device: HKDevice? {
        return HKDevice(
            name: "CGMBLEKit",
            manufacturer: "Dexcom",
            model: "G6",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: String(CGMBLEKitVersionNumber),
            localIdentifier: nil,
            udiDeviceIdentifier: "00386270000385"
        )
    }
    
    override func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
        self.cgmManagerDelegate?.deviceManager(self, logEventForDeviceIdentifier: transmitter.ID, type: type, message: message, completion: nil)
    }

    override func stateDidUpdate() {
        shareManager.delegate.notify { delegate in
            delegate?.cgmManagerDidUpdateState(self)
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
        }
    }
}


enum CalibrationError: Error {
    case unreliableState(CalibrationState)
}

extension CalibrationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreliableState:
            return LocalizedString("Glucose data is unavailable", comment: "Error description for unreliable state")
        }
    }

    var failureReason: String? {
        switch self {
        case .unreliableState(let state):
            return state.localizedDescription
        }
    }
}

extension CalibrationState {
    public var localizedDescription: String {
        switch self {
        case .known(let state):
            switch state {
            case .needCalibration7, .needCalibration14, .needFirstInitialCalibration, .needSecondInitialCalibration, .calibrationError8, .calibrationError9, .calibrationError10, .calibrationError13:
                return LocalizedString("Sensor needs calibration", comment: "The description of sensor calibration state when sensor needs calibration.")
            case .ok:
                return LocalizedString("Sensor calibration is OK", comment: "The description of sensor calibration state when sensor calibration is ok.")
            case .stopped, .sensorFailure11, .sensorFailure12, .sessionFailure15, .sessionFailure16, .sessionFailure17:
                return LocalizedString("Sensor is stopped", comment: "The description of sensor calibration state when sensor sensor is stopped.")
            case .warmup, .questionMarks:
                return LocalizedString("Sensor is warming up", comment: "The description of sensor calibration state when sensor sensor is warming up.")
            }
        case .unknown(let rawValue):
            return String(format: LocalizedString("Sensor is in unknown state %1$d", comment: "The description of sensor calibration state when raw value is unknown. (1: missing data details)"), rawValue)
        }
    }
}

// MARK: - AlertResponder implementation
extension G5CGMManager {
    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}

// MARK: - AlertSoundVendor implementation
extension G5CGMManager {
    public func getSoundBaseURL() -> URL? { return nil }
    public func getSounds() -> [Alert.Sound] { return [] }
}

// MARK: - AlertResponder implementation
extension G6CGMManager {
    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}

// MARK: - AlertSoundVendor implementation
extension G6CGMManager {
    public func getSoundBaseURL() -> URL? { return nil }
    public func getSounds() -> [Alert.Sound] { return [] }
}

