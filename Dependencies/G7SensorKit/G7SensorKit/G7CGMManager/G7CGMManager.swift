//
//  G7CGMManager.swift
//  CGMBLEKit
//
//  Created by Pete Schwamb on 9/24/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import os.log
import HealthKit



public protocol G7StateObserver: AnyObject {
    func g7StateDidUpdate(_ state: G7CGMManagerState?)
    func g7ConnectionStatusDidChange()
}

public class G7CGMManager: CGMManager {
    private let log = OSLog(category: "G7CGMManager")

    public var state: G7CGMManagerState {
        return lockedState.value
    }

    private func setState(_ changes: (_ state: inout G7CGMManagerState) -> Void) -> Void {
        return setStateWithResult(changes)
    }

    @discardableResult
    private func mutateState(_ changes: (_ state: inout G7CGMManagerState) -> Void) -> G7CGMManagerState {
        return setStateWithResult({ (state) -> G7CGMManagerState in
            changes(&state)
            return state
        })
    }

    private func setStateWithResult<ReturnType>(_ changes: (_ state: inout G7CGMManagerState) -> ReturnType) -> ReturnType {
        var oldValue: G7CGMManagerState!
        var returnType: ReturnType!
        let newValue = lockedState.mutate { (state) in
            oldValue = state
            returnType = changes(&state)
        }

        if oldValue != newValue {
            delegate.notify { delegate in
                delegate?.cgmManagerDidUpdateState(self)
                delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
            }

            g7StateObservers.forEach { (observer) in
                observer.g7StateDidUpdate(newValue)
            }
        }

        return returnType
    }
    private let lockedState: Locked<G7CGMManagerState>

    private let g7StateObservers = WeakSynchronizedSet<G7StateObserver>()

    public weak var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            return delegate.delegate
        }
        set {
            delegate.delegate = newValue
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            return delegate.queue
        }
        set {
            delegate.queue = newValue
        }
    }

    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()

    public var providesBLEHeartbeat: Bool = true

    public var managedDataInterval: TimeInterval? {
        return .hours(3)
    }

    public var shouldSyncToRemoteService: Bool {
        return state.uploadReadings
    }

    public var glucoseDisplay: GlucoseDisplayable? {
        return latestReading
    }

    public var isScanning: Bool {
        return sensor.isScanning
    }

    public var isConnected: Bool {
        return sensor.isConnected
    }

    public var sensorName: String? {
        return state.sensorID
    }

    public var sensorActivatedAt: Date? {
        return state.activatedAt
    }

    public var sensorExpiresAt: Date? {
        guard let activatedAt = sensorActivatedAt else {
            return nil
        }
        return activatedAt.addingTimeInterval(G7Sensor.lifetime)
    }

    public var sensorEndsAt: Date? {
        guard let activatedAt = sensorActivatedAt else {
            return nil
        }
        return activatedAt.addingTimeInterval(G7Sensor.lifetime + G7Sensor.gracePeriod)
    }


    public var sensorFinishesWarmupAt: Date? {
        guard let activatedAt = sensorActivatedAt else {
            return nil
        }
        return activatedAt.addingTimeInterval(G7Sensor.warmupDuration)
    }

    public var latestReading: G7GlucoseMessage? {
        return state.latestReading
    }

    public var lastConnect: Date? {
        return state.latestConnect
    }

    public var latestReadingTimestamp: Date? {
        return state.latestReadingTimestamp
    }

    public var uploadReadings: Bool {
        get {
            return state.uploadReadings
        }
        set {
            mutateState { state in
                state.uploadReadings = newValue
            }
        }
    }

    public let sensor: G7Sensor

    public var cgmManagerStatus: LoopKit.CGMManagerStatus {
        return CGMManagerStatus(hasValidSensorSession: true, device: device)
    }

    public var lifecycleState: G7SensorLifecycleState {
        if state.sensorID == nil {
            return .searching
        }
        if let sensorEndsAt = sensorEndsAt, sensorEndsAt.timeIntervalSinceNow < 0 {
            return .expired
        }
        if let algorithmState = latestReading?.algorithmState {
            if algorithmState.isInWarmup {
                return .warmup
            }
            if algorithmState.sensorFailed {
                return .failed
            }
        }
        if let sensorExpiresAt = sensorExpiresAt, sensorExpiresAt.timeIntervalSinceNow < 0 {
            return .gracePeriod
        }
        return .ok
    }


    public func fetchNewDataIfNeeded(_ completion: @escaping (LoopKit.CGMReadingResult) -> Void) {
        sensor.resumeScanning()
        completion(.noData)
    }

    public init() {
        lockedState = Locked(G7CGMManagerState())
        sensor = G7Sensor(sensorID: nil)
        sensor.delegate = self
    }

    public required init?(rawState: RawStateValue) {
        let state = G7CGMManagerState(rawValue: rawState)
        lockedState = Locked(state)
        sensor = G7Sensor(sensorID: state.sensorID)
        sensor.delegate = self
    }

    public var rawState: RawStateValue {
        return state.rawValue
    }

    public var debugDescription: String {
        let lines = [
            "## G7CGMManager",
            "sensorID: \(String(describing: state.sensorID))",
            "activatedAt: \(String(describing: state.activatedAt))",
            "latestReading: \(String(describing: state.latestReading))",
            "latestReadingTimestamp: \(String(describing: state.latestReadingTimestamp))",
            "latestConnect: \(String(describing: state.latestConnect))",
            "uploadReadings: \(String(describing: state.uploadReadings))",
        ]
        return lines.joined(separator: "\n")
    }

    public func acknowledgeAlert(alertIdentifier: LoopKit.Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    public func getSoundBaseURL() -> URL? { return nil }
    public func getSounds() -> [Alert.Sound] { return [] }

    public static let pluginIdentifier: String = "G7CGMManager"

    public let localizedTitle = LocalizedString("Dexcom G7", comment: "CGM display title")

    public let isOnboarded = true   // No distinction between created and onboarded

    public var appURL: URL? {
        return nil
    }

    public func scanForNewSensor() {
        logDeviceCommunication("Forgetting existing sensor and starting scan for new sensor.", type: .connection)

        mutateState { state in
            state.sensorID = nil
            state.activatedAt = nil
        }
        sensor.scanForNewSensor()
    }

    private var device: HKDevice? {
        return HKDevice(
            name: state.sensorID ?? "Unknown",
            manufacturer: "Dexcom",
            model: "G7",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: "CGMBLEKit" + String(G7SensorKitVersionNumber),
            localIdentifier: nil,
            udiDeviceIdentifier: "00386270001863"
        )
    }

    func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
        self.cgmManagerDelegate?.deviceManager(self, logEventForDeviceIdentifier: state.sensorID, type: type, message: message, completion: nil)
    }

    private func updateDelegate(with result: CGMReadingResult) {
        delegateQueue?.async {
            self.cgmManagerDelegate?.cgmManager(self, hasNew: result)
        }
    }
}

extension G7CGMManager {
    // MARK: - G7StateObserver

    public func addStateObserver(_ observer: G7StateObserver, queue: DispatchQueue) {
        g7StateObservers.insert(observer, queue: queue)
    }

    public func removeStateObserver(_ observer: G7StateObserver) {
        g7StateObservers.removeElement(observer)
    }
}

extension G7CGMManager: G7SensorDelegate {
    public func sensor(_ sensor: G7Sensor, didDiscoverNewSensor name: String, activatedAt: Date) -> Bool {
        logDeviceCommunication("New sensor \(name) discovered, activated at \(activatedAt)", type: .connection)

        let shouldSwitchToNewSensor = true

        if shouldSwitchToNewSensor {
            mutateState { state in
                state.sensorID = name
                state.activatedAt = activatedAt
            }
            let event = PersistedCgmEvent(
                date: activatedAt,
                type: .sensorStart,
                deviceIdentifier: name,
                expectedLifetime: .hours(24 * 10 + 12),
                warmupPeriod: .hours(2)
            )
            delegate.notify { delegate in
                delegate?.cgmManager(self, hasNew: [event])
            }
        }

        return shouldSwitchToNewSensor
    }

    public func sensorDidConnect(_ sensor: G7Sensor, name: String) {
        mutateState { state in
            state.latestConnect = Date()
        }
        logDeviceCommunication("Sensor connected", type: .connection)
    }

    public func sensorDisconnected(_ sensor: G7Sensor, suspectedEndOfSession: Bool) {
        logDeviceCommunication("Sensor disconnected: suspectedEndOfSession=\(suspectedEndOfSession)", type: .connection)
        if suspectedEndOfSession {
            scanForNewSensor()
        }
    }

    public func sensor(_ sensor: G7Sensor, didError error: Error) {
        logDeviceCommunication("Sensor error \(error)", type: .error)
    }

    public func sensor(_ sensor: G7Sensor, didRead message: G7GlucoseMessage) {

        guard message != latestReading else {
            logDeviceCommunication("Sensor reading duplicate: \(message)", type: .error)
            updateDelegate(with: .noData)
            return
        }

        guard let activationDate = sensor.activationDate else {
            logDeviceCommunication("Unable to process sensor reading without activation date.", type: .error)
            return
        }

        logDeviceCommunication("Sensor didRead \(message)", type: .receive)

        let latestReadingTimestamp = activationDate.addingTimeInterval(TimeInterval(message.glucoseTimestamp))

        mutateState { state in
            state.latestReading = message
            state.latestReadingTimestamp = latestReadingTimestamp
        }

        guard let glucose = message.glucose else {
            updateDelegate(with: .noData)
            return
        }

        guard message.hasReliableGlucose else {
            updateDelegate(with: .error(AlgorithmError.unreliableState(message.algorithmState)))
            return
        }

        let unit = HKUnit.milligramsPerDeciliter
        let quantity = HKQuantity(unit: unit, doubleValue: Double(min(max(glucose, GlucoseLimits.minimum), GlucoseLimits.maximum)))

        updateDelegate(with: .newData([
            NewGlucoseSample(
                date: latestReadingTimestamp,
                quantity: quantity,
                condition: message.condition,
                trend: message.trendType,
                trendRate: message.trendRate,
                isDisplayOnly: message.glucoseIsDisplayOnly,
                wasUserEntered: message.glucoseIsDisplayOnly,
                syncIdentifier: generateSyncIdentifier(timestamp: message.glucoseTimestamp),
                device: device
            )
        ]))
    }

    private func generateSyncIdentifier(timestamp: UInt32) -> String {
        guard let activatedAt = state.activatedAt, let sensorID = state.sensorID else {
            return "invalid"
        }

        return "\(activatedAt.timeIntervalSince1970.hours) \(sensorID) \(timestamp)"
    }

    public func sensor(_ sensor: G7Sensor, didReadBackfill backfill: [G7BackfillMessage]) {
        for msg in backfill {
            logDeviceCommunication("Sensor didReadBackfill \(msg)", type: .receive)
        }

        guard let activationDate = sensor.activationDate else {
            log.error("Unable to process backfill without activation date.")
            return
        }

        let unit = HKUnit.milligramsPerDeciliter

        let samples = backfill.compactMap { entry -> NewGlucoseSample? in
            guard let glucose = entry.glucose else {
                return nil
            }

            guard entry.hasReliableGlucose else {
                logDeviceCommunication("Backfill reading unreliable: \(entry)", type: .receive)
                return nil
            }

            let quantity = HKQuantity(unit: unit, doubleValue: Double(min(max(glucose, GlucoseLimits.minimum), GlucoseLimits.maximum)))

            return NewGlucoseSample(
                date: activationDate.addingTimeInterval(TimeInterval(entry.timestamp)),
                quantity: quantity,
                condition: entry.condition,
                trend: entry.trendType,
                trendRate: entry.trendRate,
                isDisplayOnly: entry.glucoseIsDisplayOnly,
                wasUserEntered: entry.glucoseIsDisplayOnly,
                syncIdentifier: generateSyncIdentifier(timestamp: entry.timestamp),
                device: device
            )
        }

        updateDelegate(with: .newData(samples))
    }

    public func sensorConnectionStatusDidUpdate(_ sensor: G7Sensor) {
        g7StateObservers.forEach { (observer) in
            observer.g7ConnectionStatusDidChange()
        }
    }
}

extension G7BackfillMessage {
    public var trendRate: HKQuantity? {
        guard let trend = trend else {
            return nil
        }
        return HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: trend)
    }
}

extension G7GlucoseMessage: GlucoseDisplayable {
    public var isStateValid: Bool {
        return hasReliableGlucose
    }

    public var trendRate: HKQuantity? {
        guard let trend = trend else {
            return nil
        }
        return HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: trend)
    }

    public var glucoseQuantity: HKQuantity? {
        guard let glucose = glucose else {
            return nil
        }
        return HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucose))
    }

    public var isLocal: Bool {
        return true
    }

    public var glucoseRangeCategory: LoopKit.GlucoseRangeCategory? {
        guard let glucose = glucose else {
            return nil
        }

        if glucose < GlucoseLimits.minimum {
            return .belowRange
        } else if glucose > GlucoseLimits.maximum {
            return .aboveRange
        } else {
            return nil
        }
    }
}
