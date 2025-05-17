//
//  OmniBLEPumpManager.swift
//  OmniBLE
//
//  Based on OmniKit/PumpManager/OmnipodPumpManager.swift
//  Created by Pete Schwamb on 8/4/18.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import UserNotifications
import os.log
import CoreBluetooth

public protocol PodStateObserver: AnyObject {
    func podStateDidUpdate(_ state: PodState?)
    func podConnectionStateDidChange(isConnected: Bool)
}

public enum PodCommState: Equatable {
    case noPod
    case activating
    case active
    case fault(DetailedStatus)
    case deactivating
}

public enum OmniBLEPumpManagerError: Error {
    case noPodPaired
    case podAlreadyPaired
    case insulinTypeNotConfigured
    case notReadyForCannulaInsertion
    case invalidSetting
    case communication(Error)
    case state(Error)
}

extension OmniBLEPumpManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noPodPaired:
            return LocalizedString("No pod paired", comment: "Error message shown when no pod is paired")
        case .podAlreadyPaired:
            return LocalizedString("Pod already paired", comment: "Error message shown when user cannot pair because pod is already paired")
        case .insulinTypeNotConfigured:
            return LocalizedString("Insulin type not configured", comment: "Error description for insulin type not configured")
        case .notReadyForCannulaInsertion:
            return LocalizedString("Pod is not in a state ready for cannula insertion.", comment: "Error message when cannula insertion fails because the pod is in an unexpected state")
        case .invalidSetting:
            return LocalizedString("Invalid Setting", comment: "Error description for invalid setting")
        case .communication(let error):
            if let error = error as? LocalizedError {
                return error.errorDescription
            } else {
                return String(describing: error)
            }
        case .state(let error):
            if let error = error as? LocalizedError {
                return error.errorDescription
            } else {
                return String(describing: error)
            }
        }
    }

    public var failureReason: String? {
        return nil
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noPodPaired:
            return LocalizedString("Please pair a new pod", comment: "Recovery suggestion shown when no pod is paired")
        default:
            return nil
        }
    }
}

public class OmniBLEPumpManager: DeviceManager {

    public let managerIdentifier: String = "Omnipod-Dash" // use a single token to make parsing log files easier

    public let localizedTitle = LocalizedString("Omnipod DASH", comment: "Generic title of the OmniBLE pump manager")

    static let podAlarmNotificationIdentifier = "OmniBLE:\(LoopNotificationCategory.pumpFault.rawValue)"

    public init(state: OmniBLEPumpManagerState, dateGenerator: @escaping () -> Date = Date.init) {
        self.lockedState = Locked(state)

        self.dateGenerator = dateGenerator

        let podComms = PodComms(podState: state.podState, myId: state.controllerId, podId: state.podId)
        self.lockedPodComms = Locked(podComms)

        self.podComms.delegate = self
        self.podComms.messageLogger = self

    }

    public required convenience init?(rawState: PumpManager.RawStateValue) {
        guard let state = OmniBLEPumpManagerState(rawValue: rawState) else
        {
            return nil
        }

        self.init(state: state)
    }

    public var deviceBLEName: String? {
        return self.podComms.manager?.peripheral.name
    }

    private var podComms: PodComms {
        get {
            return lockedPodComms.value
        }
        set {
            lockedPodComms.value = newValue
        }
    }
    private let lockedPodComms: Locked<PodComms>

    private let podStateObservers = WeakSynchronizedSet<PodStateObserver>()

    // Primarily used for testing
    public let dateGenerator: () -> Date

    public var state: OmniBLEPumpManagerState {
        return lockedState.value
    }

    private func setState(_ changes: (_ state: inout OmniBLEPumpManagerState) -> Void) -> Void {
        return setStateWithResult(changes)
    }

    // Status can change even when state does not, because some status changes
    // purely based on time. This provides a mechanism to evaluate status changes
    // as time progresses and trigger status updates to clients.
    private func evaluateStatus() {
        setState { state in
            // status is evaluated in the setState call
        }
    }

    private func setStateWithResult<ReturnType>(_ changes: (_ state: inout OmniBLEPumpManagerState) -> ReturnType) -> ReturnType {
        var oldValue: OmniBLEPumpManagerState!
        var returnType: ReturnType!
        var shouldNotifyStatusUpdate = false
        var oldStatus: PumpManagerStatus?

        let newValue = lockedState.mutate { (state) in
            oldValue = state
            let oldStatusEvaluationDate = state.lastStatusChange
            let oldHighlight = buildPumpStatusHighlight(for: oldValue, andDate: oldStatusEvaluationDate)
            oldStatus = status(for: oldValue)

            returnType = changes(&state)

            let newStatusEvaluationDate = Date()
            let newStatus = status(for: state)
            let newHighlight = buildPumpStatusHighlight(for: state, andDate: newStatusEvaluationDate)

            if oldStatus != newStatus || oldHighlight != newHighlight {
                shouldNotifyStatusUpdate = true
                state.lastStatusChange = newStatusEvaluationDate
            }
        }

        if oldValue.podState != newValue.podState {
            podStateObservers.forEach { (observer) in
                observer.podStateDidUpdate(newValue.podState)
            }

            if oldValue.podState?.lastInsulinMeasurements?.reservoirLevel != newValue.podState?.lastInsulinMeasurements?.reservoirLevel {
                if let lastInsulinMeasurements = newValue.podState?.lastInsulinMeasurements,
                   let reservoirLevel = lastInsulinMeasurements.reservoirLevel,
                   reservoirLevel != Pod.reservoirLevelAboveThresholdMagicNumber
                {
                    self.pumpDelegate.notify({ (delegate) in
                        self.log.info("DU: updating reservoir level %{public}@", String(describing: reservoirLevel))
                        delegate?.pumpManager(self, didReadReservoirValue: reservoirLevel, at: lastInsulinMeasurements.validTime) { _ in }
                    })
                }
            }
        }

        // Ideally we ensure that oldValue.rawValue != newValue.rawValue, but the types aren't
        // defined as equatable
        pumpDelegate.notify { (delegate) in
            delegate?.pumpManagerDidUpdateState(self)
        }

        if let oldStatus = oldStatus, shouldNotifyStatusUpdate {
            notifyStatusObservers(oldStatus: oldStatus)
        }

        return returnType
    }

    private let lockedState: Locked<OmniBLEPumpManagerState>

    private let statusObservers = WeakSynchronizedSet<PumpManagerStatusObserver>()

    private func notifyStatusObservers(oldStatus: PumpManagerStatus) {
        let status = self.status
        pumpDelegate.notify { (delegate) in
            delegate?.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }
        statusObservers.forEach { (observer) in
            observer.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }
    }

    private func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
        let podAddress = String(format: "%04X", self.state.podId)
        // Not dispatching here; if delegate queue is blocked, timestamps will be delayed
        self.pumpDelegate.delegate?.deviceManager(self, logEventForDeviceIdentifier: podAddress, type: type, message: message, completion: nil)
    }
    
    // Not persisted
    var provideHeartbeat: Bool = false

    private var lastHeartbeat: Date = .distantPast
    
    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        provideHeartbeat = mustProvideBLEHeartbeat
    }

    private func issueHeartbeatIfNeeded() {
        if self.provideHeartbeat, dateGenerator().timeIntervalSince(lastHeartbeat) > .minutes(2) {
            self.pumpDelegate.notify { (delegate) in
                delegate?.pumpManagerBLEHeartbeatDidFire(self)
            }
            self.lastHeartbeat = Date()
        }
    }

    var isConnected: Bool {
        podComms.manager?.peripheral.state == .connected
    }

    func omnipodPeripheralDidConnect(manager: PeripheralManager) {
        logDeviceCommunication("Pod connected \(manager.peripheral.identifier.uuidString)", type: .connection)
        notifyPodConnectionStateDidChange(isConnected: true)
    }

    func omnipodPeripheralDidDisconnect(peripheral: CBPeripheral, error: Error?) {
        logDeviceCommunication("Pod disconnected \(peripheral.identifier.uuidString) \(String(describing: error))", type: .connection)
        notifyPodConnectionStateDidChange(isConnected: false)
    }

    func omnipodPeripheralDidFailToConnect(peripheral: CBPeripheral, error: Error?) {
        logDeviceCommunication("Pod failed to connect \(peripheral.identifier.uuidString), \(String(describing: error))", type: .connection)
    }

    func omnipodPeripheralWasRestored(manager: PeripheralManager) {
        logDeviceCommunication("Pod peripheral was restored \(manager.peripheral.identifier.uuidString))", type: .connection)
        notifyPodConnectionStateDidChange(isConnected: manager.peripheral.state == .connected)
    }

    func notifyPodConnectionStateDidChange(isConnected: Bool) {
        podStateObservers.forEach { (observer) in
            observer.podConnectionStateDidChange(isConnected: isConnected)
        }
    }

    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()

    public let log = OSLog(category: "OmniBLEPumpManager")

    private var lastLoopRecommendation: Date?

    // MARK: - CustomDebugStringConvertible

    public var debugDescription: String {
        let lines = [
            "## OmniBLEPumpManager",
            "provideHeartbeat: \(provideHeartbeat)",
            "connected: \(isConnected)",
            "",
            "podComms: \(String(reflecting: podComms))",
            "statusObservers.count: \(statusObservers.cleanupDeallocatedElements().count)",
            "status: \(String(describing: status))",
            "",
            "podStateObservers.count: \(podStateObservers.cleanupDeallocatedElements().count)",
            "state: \(String(reflecting: state))",
        ]
        return lines.joined(separator: "\n")
    }
}

extension OmniBLEPumpManager {
    // MARK: - PodStateObserver

    public func addPodStateObserver(_ observer: PodStateObserver, queue: DispatchQueue) {
        podStateObservers.insert(observer, queue: queue)
    }

    public func removePodStateObserver(_ observer: PodStateObserver) {
        podStateObservers.removeElement(observer)
    }

    private func status(for state: OmniBLEPumpManagerState) -> PumpManagerStatus {
        return PumpManagerStatus(
            timeZone: state.timeZone,
            device: device(for: state),
            pumpBatteryChargeRemaining: nil,
            basalDeliveryState: basalDeliveryState(for: state),
            bolusState: bolusState(for: state),
            insulinType: state.insulinType,
            deliveryIsUncertain: state.podState?.needsCommsRecovery == true
        )
    }

    private func device(for state: OmniBLEPumpManagerState) -> HKDevice {
        if let podState = state.podState {
            return HKDevice(
                name: managerIdentifier,
                manufacturer: "Insulet",
                model: "Dash",
                hardwareVersion: String(podState.productId),
                firmwareVersion: podState.firmwareVersion + " " + podState.bleFirmwareVersion,
                softwareVersion: String(OmniBLEVersionNumber),
                localIdentifier: String(format:"%04X", podState.address),
                udiDeviceIdentifier: nil
            )
        } else {
            return HKDevice(
                name: managerIdentifier,
                manufacturer: "Insulet",
                model: "Dash",
                hardwareVersion: nil,
                firmwareVersion: nil,
                softwareVersion: String(OmniBLEVersionNumber),
                localIdentifier: nil,
                udiDeviceIdentifier: nil
            )
        }
    }

    private func basalDeliveryState(for state: OmniBLEPumpManagerState) -> PumpManagerStatus.BasalDeliveryState {
        guard let podState = state.podState else {
            return .active(.distantPast)
        }

        switch podCommState(for: state) {
        case .fault:
            return .active(.distantPast)
        default:
            break
        }

        switch state.suspendEngageState {
        case .engaging:
            return .suspending
        case .disengaging:
            return .resuming
        case .stable:
            break
        }

        switch state.tempBasalEngageState {
        case .engaging:
            return .initiatingTempBasal
        case .disengaging:
            return .cancelingTempBasal
        case .stable:
            if let tempBasal = podState.unfinalizedTempBasal {
                return .tempBasal(DoseEntry(tempBasal))
            }
            switch podState.suspendState {
            case .resumed(let date):
                return .active(date)
            case .suspended(let date):
                return .suspended(date)
            }
        }
    }

    private func bolusState(for state: OmniBLEPumpManagerState) -> PumpManagerStatus.BolusState {
        guard let podState = state.podState else {
            return .noBolus
        }

        switch state.bolusEngageState {
        case .engaging:
            return .initiating
        case .disengaging:
            return .canceling
        case .stable:
            if let bolus = podState.unfinalizedBolus {
                return .inProgress(DoseEntry(bolus))
            }
        }
        return .noBolus
    }

    // Returns true if there an unfinishedDose for a manual bolus (independent of whether it is finished)
    private var hasUnfinalizedManualBolus: Bool {
        if let automatic = state.podState?.unfinalizedBolus?.automatic, !automatic {
            return true
        }
        return false
    }

    // Returns true if there an unfinishedDose for a manual temp basal (independent of whether it is finished)
    private var hasUnfinalizedManualTempBasal: Bool {
        if let automatic = state.podState?.unfinalizedTempBasal?.automatic, !automatic {
            return true
        }
        return false
    }


    private var podTime: TimeInterval {
        get {
            guard let podState = state.podState else {
                return 0
            }
            let elapsed = -(podState.podTimeUpdated?.timeIntervalSinceNow ?? 0)
            let podActiveTime = podState.podTime + elapsed
            return podActiveTime
        }
    }

    // Returns a suitable beep command MessageBlock based the current beep preferences and
    // whether there is an unfinializedDose for a manual temp basal &/or a manual bolus.
    private func beepMessageBlock(beepType: BeepType) -> MessageBlock? {
        guard self.beepPreference.shouldBeepForManualCommand && !self.silencePod else {
            return nil
        }

        // Enable temp basal & basal completion beeps if there is a cooresponding manual unfinalizedDose
        let beepMessageBlock = BeepConfigCommand(
            beepType: beepType,
            tempBasalCompletionBeep: self.hasUnfinalizedManualTempBasal,
            bolusCompletionBeep: self.hasUnfinalizedManualBolus
        )

        return beepMessageBlock
    }

    private func podCommState(for state: OmniBLEPumpManagerState) -> PodCommState {
        guard let podState = state.podState else {
            return .noPod
        }
        guard podState.fault == nil else {
            return .fault(podState.fault!)
        }

        if podState.isActive {
            return .active
        } else if !podState.isSetupComplete {
            return .activating
        }
        return .deactivating // Can't be reached and thus will never be returned
    }

    public var podCommState: PodCommState {
        return podCommState(for: state)
    }

    public var podActivatedAt: Date? {
        return state.podState?.activatedAt
    }

    public var podExpiresAt: Date? {
        return state.podState?.expiresAt
    }

    public var hasActivePod: Bool {
        return state.hasActivePod
    }

    public var hasSetupPod: Bool {
        return state.hasSetupPod
    }

    // If time remaining is negative, the pod has been expired for that amount of time.
    public var podTimeRemaining: TimeInterval? {
        guard let expiresAt = state.podState?.expiresAt else { return nil }
        return expiresAt.timeIntervalSince(dateGenerator())
    }

    private var shouldWarnPodEOL: Bool {
        let eolDisplayActiveTime = Pod.timeRemainingWarningThreshold + (state.scheduledExpirationReminderOffset ?? 0.0)
        guard let podTimeRemaining = podTimeRemaining,
              podTimeRemaining > 0 && podTimeRemaining <= eolDisplayActiveTime else
        {
            return false
        }

        return true
    }

    public var durationBetweenLastPodCommAndActivation: TimeInterval? {
        guard let lastPodCommDate = state.podState?.lastInsulinMeasurements?.validTime,
              let activationTime = podActivatedAt else
        {
            return nil
        }

        return lastPodCommDate.timeIntervalSince(activationTime)
    }

    public var beepPreference: BeepPreference {
        get {
            return state.confirmationBeeps
        }
    }

    // Thread-safe
    public var silencePod: Bool {
        get {
            return state.silencePod
        }
    }

    // From last status response
    public var reservoirLevel: ReservoirLevel? {
        return state.reservoirLevel
    }

    public var podTotalDelivery: HKQuantity? {
        guard let delivery = state.podState?.lastInsulinMeasurements?.delivered else {
            return nil
        }
        return HKQuantity(unit: .internationalUnit(), doubleValue: delivery)
    }

    public var lastStatusDate: Date? {
        guard let date = state.podState?.lastInsulinMeasurements?.validTime else {
            return nil
        }
        return date
    }

    public var defaultExpirationReminderOffset: TimeInterval {
        set {
            setState { (state) in
                state.defaultExpirationReminderOffset = newValue
            }
        }
        get {
            state.defaultExpirationReminderOffset
        }
    }

    public var lowReservoirReminderValue: Double {
        set {
            setState { (state) in
                state.lowReservoirReminderValue = newValue
            }
        }
        get {
            state.lowReservoirReminderValue
        }
    }

    public var podAttachmentConfirmed: Bool {
        set {
            setState { (state) in
                state.podAttachmentConfirmed = newValue
            }
        }
        get {
            state.podAttachmentConfirmed
        }
    }

    public var initialConfigurationCompleted: Bool {
        set {
            setState { (state) in
                state.initialConfigurationCompleted = newValue
            }
        }
        get {
            state.initialConfigurationCompleted
        }
    }

    public var expiresAt: Date? {
        return state.podState?.expiresAt
    }

    public func buildPumpStatusHighlight(for state: OmniBLEPumpManagerState, andDate date: Date = Date()) -> PumpStatusHighlight? {
        if state.podState?.needsCommsRecovery == true {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString("Comms Issue", comment: "Status highlight that delivery is uncertain."),
                imageName: "exclamationmark.circle.fill",
                state: .critical)
        }

        switch podCommState(for: state) {
        case .activating:
            return PumpStatusHighlight(
                localizedMessage: LocalizedString("Finish Setup", comment: "Status highlight that when pod is activating."),
                imageName: "exclamationmark.circle.fill",
                state: .warning)
        case .deactivating:
            return PumpStatusHighlight(
                localizedMessage: LocalizedString("Finish Deactivation", comment: "Status highlight that when pod is deactivating."),
                imageName: "exclamationmark.circle.fill",
                state: .warning)
        case .noPod:
            return PumpStatusHighlight(
                localizedMessage: LocalizedString("No Pod", comment: "Status highlight that when no pod is paired."),
                imageName: "exclamationmark.circle.fill",
                state: .warning)
        case .fault(let detail):
            var message: String
            switch detail.faultEventCode.faultType {
            case .reservoirEmpty:
                message = LocalizedString("No Insulin", comment: "Status highlight message for emptyReservoir alarm.")
            case .exceededMaximumPodLife80Hrs:
                message = LocalizedString("Pod Expired", comment: "Status highlight message for podExpired alarm.")
            case .occluded:
                message = LocalizedString("Pod Occlusion", comment: "Status highlight message for occlusion alarm.")
            default:
                message = LocalizedString("Pod Error", comment: "Status highlight message for other alarm.")
            }
            return PumpStatusHighlight(
                localizedMessage: message,
                imageName: "exclamationmark.circle.fill",
                state: .critical)
        case .active:
            if let reservoirPercent = state.reservoirLevel?.percentage, reservoirPercent == 0 {
                return PumpStatusHighlight(
                    localizedMessage: LocalizedString("No Insulin", comment: "Status highlight that a pump is out of insulin."),
                    imageName: "exclamationmark.circle.fill",
                    state: .critical)
            } else if state.podState?.isSuspended == true {
                return PumpStatusHighlight(
                    localizedMessage: LocalizedString("Insulin Suspended", comment: "Status highlight that insulin delivery was suspended."),
                    imageName: "pause.circle.fill",
                    state: .warning)
            } else if date.timeIntervalSince(state.lastPumpDataReportDate ?? .distantPast) > .minutes(12) {
                return PumpStatusHighlight(
                    localizedMessage: LocalizedString("Signal Loss", comment: "Status highlight when communications with the pod haven't happened recently."),
                    imageName: "exclamationmark.circle.fill",
                    state: .critical)
            } else if isRunningManualTempBasal(for: state) {
                return PumpStatusHighlight(
                    localizedMessage: LocalizedString("Manual Basal", comment: "Status highlight when manual temp basal is running."),
                    imageName: "exclamationmark.circle.fill",
                    state: .warning)
            }
            return nil
        }
    }

    public func isRunningManualTempBasal(for state: OmniBLEPumpManagerState) -> Bool {
        if let tempBasal = state.podState?.unfinalizedTempBasal, !tempBasal.isFinished(), !tempBasal.automatic {
            return true
        }
        return false
    }

    public var reservoirLevelHighlightState: ReservoirLevelHighlightState? {
        guard let reservoirLevel = reservoirLevel else {
            return nil
        }

        switch reservoirLevel {
        case .aboveThreshold:
            return .normal
        case .valid(let value):
            if value > state.lowReservoirReminderValue {
                return .normal
            } else if value > 0 {
                return .warning
            } else {
                return .critical
            }
        }
    }

    public func buildPumpLifecycleProgress(for state: OmniBLEPumpManagerState) -> PumpLifecycleProgress? {
        switch podCommState {
        case .active:
            if shouldWarnPodEOL,
               let podTimeRemaining = podTimeRemaining
            {
                let percentCompleted = max(0, min(1, (1 - (podTimeRemaining / Pod.nominalPodLife))))
                return PumpLifecycleProgress(percentComplete: percentCompleted, progressState: .warning)
            } else if let podTimeRemaining = podTimeRemaining, podTimeRemaining <= 0 {
                // Pod is expired
                return PumpLifecycleProgress(percentComplete: 1, progressState: .critical)
            }
            return nil
        case .fault(let detail):
            if detail.faultEventCode.faultType == .exceededMaximumPodLife80Hrs {
                return PumpLifecycleProgress(percentComplete: 100, progressState: .critical)
            } else {
                if shouldWarnPodEOL,
                   let durationBetweenLastPodCommAndActivation = durationBetweenLastPodCommAndActivation
                {
                    let percentCompleted = max(0, min(1, durationBetweenLastPodCommAndActivation / Pod.nominalPodLife))
                    return PumpLifecycleProgress(percentComplete: percentCompleted, progressState: .dimmed)
                }
            }
            return nil
        case .noPod, .activating, .deactivating:
            return nil
        }
    }

    // Reset all the per pod state kept in pump manager state which doesn't span pods
    fileprivate func resetPerPodPumpManagerState() {

        // Reset any residual per pod slot based pump manager alerts
        // (i.e., all but timeOffsetChangeDetected which isn't actually used)
        let podAlerts = state.activeAlerts.filter { $0 != .timeOffsetChangeDetected }
        for alert in podAlerts {
            self.retractAlert(alert: alert)
        }

        self.setState { (state) in
            // Reset alertsWithPendingAcknowledgment which are all pod slot based
            state.alertsWithPendingAcknowledgment = []

            // Reset other miscellaneous state variables that are actually per pod
            state.podAttachmentConfirmed = false
            state.acknowledgedTimeOffsetAlert = false
        }
    }

    // MARK: - Pod comms

    private func prepForNewPod() {

        setState { state in
            state.previousPodState = state.podState

            if state.controllerId == CONTROLLER_ID {
                // Switch from using the common fixed controllerId to a created semi-unique one
                state.controllerId = createControllerId()
                state.podId = state.controllerId + 1
                self.log.info("Switched controllerId from %x to %x", CONTROLLER_ID, state.controllerId)
            } else {
                // Already have a created controllerId, just need to advance podId for the next pod
                let lastPodId = state.podId
                state.podId = nextPodId(lastPodId: lastPodId)
                self.log.info("Advanced podId from %x to %x", lastPodId, state.podId)
            }
        }
        self.podComms.prepForNewPod(myId: self.state.controllerId, podId: self.state.podId)
    }

    public func forgetPod(completion: @escaping () -> Void) {

        self.podComms.forgetPod()

        self.resetPerPodPumpManagerState()

        if let dosesToStore = state.podState?.dosesToStore {
            store(doses: dosesToStore, completion: { error in
                self.setState({ (state) in
                    if error != nil {
                        state.unstoredDoses.append(contentsOf: dosesToStore)
                    }
                })
                self.prepForNewPod()
                completion()
            })
        } else {
            prepForNewPod()
            completion()
        }
    }


    // MARK: Testing

    #if targetEnvironment(simulator)
    private func jumpStartPod(lotNo: UInt32, lotSeq: UInt32, fault: DetailedStatus? = nil, startDate: Date? = nil, mockFault: Bool) {
        let start = startDate ?? Date()
        let fakeLtk = Data(hexadecimalString: "fedcba98765432100123456789abcdef")!
        var podState = PodState(address: state.podId, ltk: fakeLtk,
            firmwareVersion: "jumpstarted", bleFirmwareVersion: "jumpstarted",
            lotNo: lotNo, lotSeq: lotSeq, productId: dashProductId,
                                bleIdentifier: "0000-0000", insulinType: insulinType ?? .novolog)

        podState.setupProgress = .podPaired
        podState.activatedAt = start
        podState.expiresAt = start + .hours(72)

        let fault = mockFault ? try? DetailedStatus(encodedData: Data(hexadecimalString: "020f0000000900345c000103ff0001000005ae056029")!) : nil
        podState.fault = fault

        self.podComms = PodComms(podState: podState, myId: state.controllerId, podId: state.podId)

        self.podComms.delegate = self
        self.podComms.messageLogger = self

        self.resetPerPodPumpManagerState()

        setState({ (state) in
            state.updatePodStateFromPodComms(podState)
            state.scheduledExpirationReminderOffset = state.defaultExpirationReminderOffset
        })
    }
    #endif

    // MARK: - Pairing

    func connectToNewPod(completion: @escaping (Result<OmniBLE, Error>) -> Void) {
        podComms.connectToNewPod { result in
            if case .success = result {
                self.pumpDelegate.notify { (delegate) in
                    delegate?.pumpManagerPumpWasReplaced(self)
                }
            }
            completion(result)
        }
    }

    // Called on the main thread
    public func pairAndPrime(completion: @escaping (PumpManagerResult<TimeInterval>) -> Void) {
        #if targetEnvironment(simulator)
        // If we're in the simulator, create a mock PodState
        let mockFaultDuringPairing = false
        let mockCommsErrorDuringPairing = false
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(2)) {
            self.jumpStartPod(lotNo: 135601809, lotSeq: 0800525, mockFault: mockFaultDuringPairing)
            let fault: DetailedStatus? = self.setStateWithResult({ (state) in
                var podState = state.podState
                podState?.setupProgress = .priming
                state.updatePodStateFromPodComms(podState)
                return state.podState?.fault
            })
            if let fault = fault {
                completion(.failure(PumpManagerError.deviceState(PodCommsError.podFault(fault: fault))))
            } else if mockCommsErrorDuringPairing {
                completion(.failure(PumpManagerError.communication(PodCommsError.noResponse)))
            } else {
                let mockPrimeDuration = TimeInterval(.seconds(3))
                completion(.success(mockPrimeDuration))
            }
        }
        #else
        let primeSession = { (result: PodComms.SessionRunResult) in
            switch result {
            case .success(let session):
                // We're on the session queue
                session.assertOnSessionQueue()

                self.log.default("Beginning pod prime")

                // Clean up any previously un-stored doses if needed
                let unstoredDoses = self.state.unstoredDoses
                if self.store(doses: unstoredDoses, in: session) {
                    self.setState({ (state) in
                        state.unstoredDoses.removeAll()
                    })
                }

                do {
                    let primeFinishedAt = try session.prime()
                    completion(.success(primeFinishedAt))
                } catch let error {
                    completion(.failure(.communication(error as? LocalizedError)))
                }
            case .failure(let error):
                completion(.failure(.communication(error)))
            }
        }

        let needsPairing = setStateWithResult({ (state) -> Bool in
            guard let podState = state.podState else {
                return true // Needs pairing
            }

            // Return true if not yet paired
            return podState.setupProgress.isPaired == false
        })

        if needsPairing {

            self.log.default("Pairing pod before priming")

            guard let insulinType = insulinType else {
                completion(.failure(.configuration(OmniBLEPumpManagerError.insulinTypeNotConfigured)))
                return
            }

            connectToNewPod(completion: { result in
                switch result {
                case .failure(let error):
                    completion(.failure(.communication(error as? LocalizedError)))
                case .success:
                    self.podComms.pairAndSetupPod(timeZone: .currentFixed, insulinType: insulinType, messageLogger: self)
                    { (result) in

                        self.resetPerPodPumpManagerState()

                        // Calls completion
                        primeSession(result)
                    }

                }

            })
        } else {
            self.log.default("Pod already paired. Continuing.")

            self.podComms.runSession(withName: "Prime pod") { (result) in
                // Calls completion
                primeSession(result)
            }
        }
        #endif
    }

    // Called on the main thread
    public func insertCannula(completion: @escaping (Result<TimeInterval,OmniBLEPumpManagerError>) -> Void) {
        
        #if targetEnvironment(simulator)
        let mockDelay = TimeInterval(seconds: 3)
        let mockFaultDuringInsertCannula = false
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + mockDelay) {
            let result = self.setStateWithResult({ (state) -> Result<TimeInterval,OmniBLEPumpManagerError> in
                if mockFaultDuringInsertCannula {
                    let fault = try! DetailedStatus(encodedData: Data(hexadecimalString: "020d0000000e00c36a020703ff020900002899080082")!)
                    var podState = state.podState
                    podState?.fault = fault
                    state.updatePodStateFromPodComms(podState)
                    return .failure(OmniBLEPumpManagerError.communication(PodCommsError.podFault(fault: fault)))
                }

                // Mock success
                var podState = state.podState
                podState?.setupProgress = .completed
                state.updatePodStateFromPodComms(podState)
                return .success(mockDelay)
            })

            completion(result)
        }
        #else
        let preError = setStateWithResult({ (state) -> OmniBLEPumpManagerError? in
            guard let podState = state.podState, podState.readyForCannulaInsertion else
            {
                return .notReadyForCannulaInsertion
            }

            state.scheduledExpirationReminderOffset = state.defaultExpirationReminderOffset

            guard podState.setupProgress.needsCannulaInsertion else {
                return .podAlreadyPaired
            }

            return nil
        })

        if let error = preError {
            completion(.failure(.state(error)))
            return
        }

        let timeZone = self.state.timeZone

        self.podComms.runSession(withName: "Insert cannula") { (result) in
            switch result {
            case .success(let session):
                do {
                    if self.state.podState?.setupProgress.needsInitialBasalSchedule == true {
                        let scheduleOffset = timeZone.scheduleOffset(forDate: Date())
                        try session.programInitialBasalSchedule(self.state.basalSchedule, scheduleOffset: scheduleOffset)

                        session.dosesForStorage() { (doses) -> Bool in
                            return self.store(doses: doses, in: session)
                        }
                    }

                    let expirationReminderTime = Pod.nominalPodLife - self.state.defaultExpirationReminderOffset
                    let alerts: [PodAlert] = [
                        .expirationReminder(offset: self.podTime, absAlertTime: self.state.defaultExpirationReminderOffset > 0 ? expirationReminderTime : 0),
                        .lowReservoir(units: self.state.lowReservoirReminderValue)
                    ]

                    let finishWait = try session.insertCannula(optionalAlerts: alerts, silent: self.silencePod)
                    completion(.success(finishWait))
                } catch let error {
                    completion(.failure(.communication(error)))
                }
            case .failure(let error):
                completion(.failure(.communication(error)))
            }
        }
        #endif
    }

    public func checkCannulaInsertionFinished(completion: @escaping (OmniBLEPumpManagerError?) -> Void) {
        #if targetEnvironment(simulator)
        completion(nil)
        #else
        self.podComms.runSession(withName: "Check cannula insertion finished") { (result) in
            switch result {
            case .success(let session):
                do {
                    try session.checkInsertionCompleted()
                    completion(nil)
                } catch let error {
                    self.log.error("Failed to fetch pod status: %{public}@", String(describing: error))
                    completion(.communication(error))
                }
            case .failure(let error):
                self.log.error("Failed to fetch pod status: %{public}@", String(describing: error))
                completion(.communication(error))
            }
        }
        #endif
    }

    public func getPodStatus(completion: ((_ result: PumpManagerResult<StatusResponse>) -> Void)? = nil) {
        guard state.hasActivePod else {
            completion?(.failure(PumpManagerError.configuration(OmniBLEPumpManagerError.noPodPaired)))
            return
        }

        podComms.runSession(withName: "Get pod status") { (result) in
            do {
                switch result {
                case .success(let session):
                    let status = try session.getStatus()
                    session.dosesForStorage({ (doses) -> Bool in
                        self.store(doses: doses, in: session)
                    })
                    completion?(.success(status))
                case .failure(let error):
                    self.evaluateStatus() 
                    throw error
                }
                self.issueHeartbeatIfNeeded()
            } catch let error {
                completion?(.failure(.communication(error as? LocalizedError)))
                self.log.error("Failed to fetch pod status: %{public}@", String(describing: error))
            }
        }
    }

    public func getDetailedStatus(completion: ((_ result: PumpManagerResult<DetailedStatus>) -> Void)? = nil) {

        // use hasSetupPod here instead of hasActivePod as DetailedStatus can be read with a faulted Pod
        guard self.hasSetupPod else {
            completion?(.failure(PumpManagerError.configuration(OmniBLEPumpManagerError.noPodPaired)))
            return
        }

        podComms.runSession(withName: "Get detailed status") { (result) in
            do {
                switch result {
                case .success(let session):
                    let beepBlock = self.beepMessageBlock(beepType: .bipBip)
                    let detailedStatus = try session.getDetailedStatus(beepBlock: beepBlock)
                    session.dosesForStorage({ (doses) -> Bool in
                        self.store(doses: doses, in: session)
                    })
                    completion?(.success(detailedStatus))
                case .failure(let error):
                    throw error
                }
            } catch let error {
                completion?(.failure(.communication(error as? LocalizedError)))
                self.log.error("Failed to fetch detailed status: %{public}@", String(describing: error))
            }
        }
    }


    // MARK: - Pump Commands

    public func acknowledgePodAlerts(_ alertsToAcknowledge: AlertSet, completion: @escaping (_ alerts: AlertSet?) -> Void) {
        guard self.hasActivePod else {
            completion(nil)
            return
        }

        self.podComms.runSession(withName: "Acknowledge Alerts") { (result) in
            let session: PodCommsSession
            switch result {
            case .success(let s):
                session = s
            case .failure:
                completion(nil)
                return
            }

            do {
                let beepBlock = self.beepMessageBlock(beepType: .bipBip)
                let alerts = try session.acknowledgeAlerts(alerts: alertsToAcknowledge, beepBlock: beepBlock)
                completion(alerts)
            } catch {
                completion(nil)
            }
        }
    }

    public func setTime(completion: @escaping (OmniBLEPumpManagerError?) -> Void) {

        guard state.hasActivePod else {
            completion(OmniBLEPumpManagerError.noPodPaired)
            return
        }

        guard state.podState?.setupProgress == .completed else {
            // A cancel delivery command before pod setup is complete will fault the pod
            completion(.state(PodCommsError.setupNotComplete))
            return
        }

        guard state.podState?.unfinalizedBolus?.isFinished() != false else {
            completion(.state(PodCommsError.unfinalizedBolus))
            return
        }

        let timeZone = TimeZone.currentFixed
        self.podComms.runSession(withName: "Set time zone") { (result) in
            switch result {
            case .success(let session):
                do {
                    let beep = self.silencePod ? false : self.beepPreference.shouldBeepForManualCommand
                    let _ = try session.setTime(timeZone: timeZone, basalSchedule: self.state.basalSchedule, date: Date(), acknowledgementBeep: beep)
                    self.clearSuspendReminder()
                    self.setState { (state) in
                        state.timeZone = timeZone
                    }
                    completion(nil)
                } catch let error {
                    completion(.communication(error))
                }
            case .failure(let error):
                completion(.communication(error))
            }
        }
    }

    public func setBasalSchedule(_ schedule: BasalSchedule, completion: @escaping (Error?) -> Void) {
        let shouldContinue = setStateWithResult({ (state) -> PumpManagerResult<Bool> in
            guard state.hasActivePod else {
                // If there's no active pod yet, save the basal schedule anyway
                state.basalSchedule = schedule
                return .success(false)
            }

            guard state.podState?.setupProgress == .completed else {
                // A cancel delivery command before pod setup is complete will fault the pod
                return .failure(PumpManagerError.deviceState(PodCommsError.setupNotComplete))
            }

            guard state.podState?.unfinalizedBolus?.isFinished() != false else {
                return .failure(.deviceState(PodCommsError.unfinalizedBolus))
            }

            return .success(true)
        })

        switch shouldContinue {
        case .success(true):
            break
        case .success(false):
            completion(nil)
            return
        case .failure(let error):
            completion(error)
            return
        }

        let timeZone = self.state.timeZone

        self.podComms.runSession(withName: "Save Basal Profile") { (result) in
            do {
                switch result {
                case .success(let session):
                    let scheduleOffset = timeZone.scheduleOffset(forDate: Date())
                    let result = session.cancelDelivery(deliveryType: .all)
                    switch result {
                    case .certainFailure(let error):
                        throw error
                    case .unacknowledged(let error):
                        throw error
                    case .success:
                        break
                    }
                    let beep = self.silencePod ? false : self.beepPreference.shouldBeepForManualCommand
                    let _ = try session.setBasalSchedule(schedule: schedule, scheduleOffset: scheduleOffset, acknowledgementBeep: beep)
                    self.clearSuspendReminder()

                    self.setState { (state) in
                        state.basalSchedule = schedule
                    }
                    completion(nil)
                case .failure(let error):
                    throw error
                }
            } catch let error {
                self.log.error("Save basal profile failed: %{public}@", String(describing: error))
                completion(error)
            }
        }
    }

    // Called on the main thread.
    // The UI is responsible for serializing calls to this method;
    // it does not handle concurrent calls.
    public func deactivatePod(completion: @escaping (OmniBLEPumpManagerError?) -> Void) {
        #if targetEnvironment(simulator)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(2)) {
            completion(nil)
        }
        #else
        guard self.state.podState != nil else {
            completion(OmniBLEPumpManagerError.noPodPaired)
            return
        }

        self.podComms.runSession(withName: "Deactivate pod") { (result) in
            switch result {
            case .success(let session):
                do {
                    try session.deactivatePod()
                    completion(nil)
                } catch let error {
                    completion(OmniBLEPumpManagerError.communication(error))
                }
            case .failure(let error):
                completion(OmniBLEPumpManagerError.communication(error))
            }
        }
        #endif
    }

    public func playTestBeeps(completion: @escaping (Error?) -> Void) {
        guard self.hasActivePod else {
            completion(OmniBLEPumpManagerError.noPodPaired)
            return
        }
        guard state.podState?.unfinalizedBolus?.scheduledCertainty == .uncertain || state.podState?.unfinalizedBolus?.isFinished() != false else {
            self.log.info("Skipping Play Test Beeps due to bolus still in progress.")
            completion(PodCommsError.unfinalizedBolus)
            return
        }

        self.podComms.runSession(withName: "Play Test Beeps") { (result) in
            switch result {
            case .success(let session):
                // preserve the pod's completion beep state which gets reset playing beeps
                let enabled: Bool = self.silencePod ? false : self.beepPreference.shouldBeepForManualCommand
                let result = session.beepConfig(
                    beepType: .bipBeepBipBeepBipBeepBipBeep,
                    tempBasalCompletionBeep: enabled && self.hasUnfinalizedManualTempBasal,
                    bolusCompletionBeep: enabled && self.hasUnfinalizedManualBolus
                )

                switch result {
                case .success:
                    completion(nil)
                case .failure(let error):
                    completion(error)
                }
            case .failure(let error):
                completion(error)
            }
        }
    }

    public func readPulseLog(completion: @escaping (Result<String, Error>) -> Void) {
        // use hasSetupPod here instead of hasActivePod as PodInfo can be read with a faulted Pod
        guard self.hasSetupPod else {
            completion(.failure(OmniBLEPumpManagerError.noPodPaired))
            return
        }
        guard state.podState?.isFaulted == true || state.podState?.unfinalizedBolus?.scheduledCertainty == .uncertain || state.podState?.unfinalizedBolus?.isFinished() != false else
        {
            self.log.info("Skipping Read Pulse Log due to bolus still in progress.")
            completion(.failure(PodCommsError.unfinalizedBolus))
            return
        }

        self.podComms.runSession(withName: "Read Pulse Log") { (result) in
            switch result {
            case .success(let session):
                do {
                    // read the most recent 50 entries from the pulse log
                    let beepBlock = self.beepMessageBlock(beepType: .bipBeeeeep)
                    let podInfoResponse = try session.readPodInfo(podInfoResponseSubType: .pulseLogRecent, beepBlock: beepBlock)
                    guard let podInfoPulseLogRecent = podInfoResponse.podInfo as? PodInfoPulseLogRecent else {
                        self.log.error("Unable to decode Pulse Log: %s", String(describing: podInfoResponse))
                        throw PodCommsError.unexpectedResponse(response: .podInfoResponse)
                    }
                    let lastPulseNumber = Int(podInfoPulseLogRecent.indexLastEntry)
                    let str = pulseLogString(pulseLogEntries: podInfoPulseLogRecent.pulseLog, lastPulseNumber: lastPulseNumber)
                    completion(.success(str))
                } catch let error {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func readPulseLogPlus(completion: @escaping (Result<String, Error>) -> Void) {
        // use hasSetupPod here instead of hasActivePod as PodInfo can be read with a faulted Pod
        guard self.hasSetupPod else {
            completion(.failure(OmniBLEPumpManagerError.noPodPaired))
            return
        }
        guard state.podState?.isFaulted == true || state.podState?.unfinalizedBolus?.scheduledCertainty == .uncertain || state.podState?.unfinalizedBolus?.isFinished() != false else
        {
            self.log.info("Skipping Read Pulse Log Plus due to bolus still in progress.")
            completion(.failure(PodCommsError.unfinalizedBolus))
            return
        }

        podComms.runSession(withName: "Read Pulse Log Plus") { (result) in
            do {
                switch result {
                case .success(let session):
                    let beepBlock = self.beepMessageBlock(beepType: .bipBeeeeep)
                    let podInfoResponse = try session.readPodInfo(podInfoResponseSubType: .pulseLogPlus, beepBlock: beepBlock)
                    guard let podInfoPulseLogPlus = podInfoResponse.podInfo as? PodInfoPulseLogPlus else {
                        self.log.error("Unable to decode Pulse Log Plus: %s", String(describing: podInfoResponse))
                        throw PodCommsError.unexpectedResponse(response: .podInfoResponse)
                    }
                    let str = pulseLogPlusString(podInfoPulseLogPlus: podInfoPulseLogPlus)
                    completion(.success(str))
                case .failure(let error):
                    throw error
                }
            } catch let error {
                completion(.failure(error))
            }
        }
    }

    public func readActivationTime(completion: @escaping (Result<String, Error>) -> Void) {
        // use hasSetupPod here instead of hasActivePod as PodInfo can be read with a faulted Pod
        guard self.hasSetupPod else {
            completion(.failure(OmniBLEPumpManagerError.noPodPaired))
            return
        }

        podComms.runSession(withName: "Read Activation Time") { (result) in
            do {
                switch result {
                case .success(let session):
                    let beepBlock = self.beepMessageBlock(beepType: .beepBeep)
                    let podInfoResponse = try session.readPodInfo(podInfoResponseSubType: .activationTime, beepBlock: beepBlock)
                    guard let podInfoActivationTime = podInfoResponse.podInfo as? PodInfoActivationTime else {
                        self.log.error("Unable to decode Activation Time: %s", String(describing: podInfoResponse))
                        throw PodCommsError.unexpectedResponse(response: .podInfoResponse)
                    }
                    let str = activationTimeString(podInfoActivationTime: podInfoActivationTime)
                    completion(.success(str))
                case .failure(let error):
                    throw error
                }
            } catch let error {
                completion(.failure(error))
            }
        }
    }

    public func readTriggeredAlerts(completion: @escaping (Result<String, Error>) -> Void) {
        // use hasSetupPod here instead of hasActivePod as PodInfo can be read with a faulted Pod
        guard self.hasSetupPod else {
            completion(.failure(OmniBLEPumpManagerError.noPodPaired))
            return
        }

        podComms.runSession(withName: "Read Triggered Alerts") { (result) in
            do {
                switch result {
                case .success(let session):
                    let beepBlock = self.beepMessageBlock(beepType: .beepBeep)
                    let podInfoResponse = try session.readPodInfo(podInfoResponseSubType: .triggeredAlerts, beepBlock: beepBlock)
                    guard let podInfoTriggeredAlerts = podInfoResponse.podInfo as? PodInfoTriggeredAlerts else {
                        self.log.error("Unable to decode Read Triggered Alerts: %s", String(describing: podInfoResponse))
                        throw PodCommsError.unexpectedResponse(response: .podInfoResponse)
                    }
                    let str = triggeredAlertsString(podInfoTriggeredAlerts: podInfoTriggeredAlerts)
                    completion(.success(str))
                case .failure(let error):
                    throw error
                }
            } catch let error {
                completion(.failure(error))
            }
        }
    }

    public func setConfirmationBeeps(newPreference: BeepPreference, completion: @escaping (OmniBLEPumpManagerError?) -> Void) {

        // If there isn't an active pod or the pod is currently silenced,
        // just need to update the internal state without any pod commands.
        let name = String(format: "Set Beep Preference to %@", String(describing: newPreference))
        if !self.hasActivePod || self.silencePod {
            self.log.default("%{public}@ for internal state only", name)
            self.setState { state in
                state.confirmationBeeps = newPreference
            }
            completion(nil)
            return
        }

        self.podComms.runSession(withName: name) { (result) in
            switch result {
            case .success(let session):
                // enable/disable Pod completion beep state for any unfinalized manual insulin delivery
                let enabled = newPreference.shouldBeepForManualCommand
                let beepType: BeepType = enabled ? .bipBip : .noBeepNonCancel
                let result = session.beepConfig(
                    beepType: beepType,
                    tempBasalCompletionBeep: enabled && self.hasUnfinalizedManualTempBasal,
                    bolusCompletionBeep: enabled && self.hasUnfinalizedManualBolus
                )

                switch result {
                case .success:
                    self.setState { state in
                        state.confirmationBeeps = newPreference
                    }
                    completion(nil)
                case .failure(let error):
                    completion(.communication(error))
                }
            case .failure(let error):
                completion(.communication(error))
            }
        }
    }

    // Reconfigures all active alerts in pod to be silent or not as well as sets/clears the
    // self.silencePod state variable which silences all confirmation beeping when enabled.
    public func setSilencePod(silencePod: Bool, completion: @escaping (OmniBLEPumpManagerError?) -> Void) {

        let name = String(format: "%@ Pod", silencePod ? "Silence" : "Unsilence")
        // allow Silence Pod changes without an active Pod
        guard self.hasActivePod else {
            self.log.default("%{public}@", name)
            self.setState { state in
                state.silencePod = silencePod
            }
            completion(nil)
            return
        }

        self.podComms.runSession(withName: name) { (result) in

            let session: PodCommsSession
            switch result {
            case .success(let s):
                session = s
            case .failure(let error):
                completion(.communication(error))
                return
            }

            guard let configuredAlerts = self.state.podState?.configuredAlerts,
                  let activeAlertSlots = self.state.podState?.activeAlertSlots,
                  let reservoirLevel = self.state.podState?.lastInsulinMeasurements?.reservoirLevel?.rawValue else
            {
                self.log.error("Missing podState") // should never happen
                completion(OmniBLEPumpManagerError.noPodPaired)
                return
            }

            let beepBlock: MessageBlock?
            if !self.beepPreference.shouldBeepForManualCommand {
                // No enabled completion beeps to worry about for any in-progress manual delivery
                beepBlock = nil
            } else if silencePod {
                // Disable completion beeps for any in-progress manual delivery w/o beeping
                beepBlock = BeepConfigCommand(beepType: .noBeepNonCancel)
            } else {
                // Emit a confirmation beep and enable completion beeps for any in-progress manual delivery
                beepBlock = BeepConfigCommand(
                    beepType: .bipBip,
                    tempBasalCompletionBeep: self.hasUnfinalizedManualTempBasal,
                    bolusCompletionBeep: self.hasUnfinalizedManualBolus
                )
            }

            let podAlerts = regeneratePodAlerts(silent: silencePod, configuredAlerts: configuredAlerts, activeAlertSlots: activeAlertSlots, currentPodTime: self.podTime, currentReservoirLevel: reservoirLevel)
            do {
                // Since non-responsive pod comms are currently only resolved for insulin related commands,
                // it's possible that a response from a previous successful pod alert configuration can be lost
                // and thus the alert won't get reset here when reconfiguring pod alerts with a new silence pod state.
                let acknowledgeAll = true   // protect against lost alert configuration response related issues
                try session.configureAlerts(podAlerts, acknowledgeAll: acknowledgeAll, beepBlock: beepBlock)
                self.setState { (state) in
                    state.silencePod = silencePod
                }
                completion(nil)
            } catch {
                self.log.error("Configure alerts %{public}@ failed: %{public}@", String(describing: podAlerts), String(describing: error))
                completion(.communication(error))
            }
        }
    }
}

// MARK: - PumpManager
extension OmniBLEPumpManager: PumpManager {

    public static var onboardingMaximumBasalScheduleEntryCount: Int {
        return Pod.maximumBasalScheduleEntryCount
    }

    public static var onboardingSupportedMaximumBolusVolumes: [Double] {
        return onboardingSupportedBolusVolumes
    }

    public var supportedMaximumBolusVolumes: [Double] {
        return supportedBolusVolumes
    }

    public static var onboardingSupportedBolusVolumes: [Double] {
        // 0.05 units for rates between 0.05-30U
        // 0 is not a supported bolus volume
        return (1...600).map { Double($0) / Double(Pod.pulsesPerUnit) }
    }

    public var supportedBolusVolumes: [Double] {
        // 0.05 units for rates between 0.05-30U
        // 0 is not a supported bolus volume
        return (1...600).map { Double($0) / Double(Pod.pulsesPerUnit) }
    }

    public static var onboardingSupportedBasalRates: [Double] {
        // 0.05 units for rates between 0.00-30U/hr
        // 0 U/hr is a supported scheduled basal rate for Dash, but not for Eros
        return (0...600).map { Double($0) / Double(Pod.pulsesPerUnit) }
    }

    public var supportedBasalRates: [Double] {
        // 0.05 units for rates between 0.00-30U/hr
        // 0 U/hr is a supported scheduled basal rate for Dash, but not for Eros
        return (0...600).map { Double($0) / Double(Pod.pulsesPerUnit) }
    }

    public func roundToSupportedBolusVolume(units: Double) -> Double {
        // We do support rounding a 0 U volume to 0
        return supportedBolusVolumes.last(where: { $0 <= units }) ?? 0
    }

    public func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
        // We do support rounding a 0 U/hr rate to 0
        return supportedBasalRates.last(where: { $0 <= unitsPerHour }) ?? 0
    }
    
    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        TimeInterval(units / Pod.bolusDeliveryRate)
    }

    public var maximumBasalScheduleEntryCount: Int {
        return Pod.maximumBasalScheduleEntryCount
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        return Pod.minimumBasalScheduleEntryDuration
    }

    public var pumpRecordsBasalProfileStartEvents: Bool {
        return false
    }

    public var pumpReservoirCapacity: Double {
        return Pod.reservoirCapacity
    }

    public var isOnboarded: Bool { state.isOnboarded }

    public var insulinType: InsulinType? {
        get {
            return self.state.insulinType
        }
        set {
            if let insulinType = newValue {
                self.setState { (state) in
                    state.insulinType = insulinType
                }
                self.podComms.updateInsulinType(insulinType)
            }
        }
    }

    public var lastSync: Date? {
        return self.state.podState?.lastInsulinMeasurements?.validTime
    }

    public var status: PumpManagerStatus {
        // Acquire the lock just once
        let state = self.state

        return status(for: state)
    }

    public var rawState: PumpManager.RawStateValue {
        return state.rawValue
    }

    public var pumpManagerDelegate: PumpManagerDelegate? {
        get {
            return pumpDelegate.delegate
        }
        set {
            pumpDelegate.delegate = newValue
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            return pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }

    // MARK: Methods

    public func completeOnboard() {
        setState({ (state) in
            state.isOnboarded = true
        })
    }
    
    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        let suspendTime: TimeInterval = .minutes(0) // untimed suspend with reminder beeps
        suspendDelivery(withSuspendReminders: suspendTime, completion: completion)
    }

    // A nil suspendReminder is untimed with no reminders beeps, a suspendReminder of 0 is untimed using reminders beeps, otherwise it
    // specifies a suspend duration implemented using an appropriate combination of suspended reminder and suspend time expired beeps.
    public func suspendDelivery(withSuspendReminders suspendReminder: TimeInterval? = nil, completion: @escaping (Error?) -> Void) {
        guard self.hasActivePod else {
            completion(OmniBLEPumpManagerError.noPodPaired)
            return
        }

        self.podComms.runSession(withName: "Suspend") { (result) in

            let session: PodCommsSession
            switch result {
            case .success(let s):
                session = s
            case .failure(let error):
                completion(error)
                return
            }

            defer {
                self.setState({ (state) in
                    state.suspendEngageState = .stable
                })
            }
            self.setState({ (state) in
                state.suspendEngageState = .engaging
            })

            // Use a beepBlock for the confirmation beep to avoid getting 3 beeps using cancel command beeps!
            let beepBlock = self.beepMessageBlock(beepType: .beeeeeep)
            let result = session.suspendDelivery(suspendReminder: suspendReminder, silent: self.silencePod, beepBlock: beepBlock)
            switch result {
            case .certainFailure(let error):
                self.log.error("Failed to suspend: %{public}@", String(describing: error))
                completion(error)
            case .unacknowledged(let error):
                self.log.error("Failed to suspend: %{public}@", String(describing: error))
                completion(error)
            case .success:
                session.dosesForStorage() { (doses) -> Bool in
                    return self.store(doses: doses, in: session)
                }
                completion(nil)
            }
        }
    }

    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        guard self.hasActivePod else {
            completion(OmniBLEPumpManagerError.noPodPaired)
            return
        }

        self.podComms.runSession(withName: "Resume") { (result) in

            let session: PodCommsSession
            switch result {
            case .success(let s):
                session = s
            case .failure(let error):
                completion(error)
                return
            }

            defer {
                self.setState({ (state) in
                    state.suspendEngageState = .stable
                })
            }

            self.setState({ (state) in
                state.suspendEngageState = .disengaging
            })

            do {
                let scheduleOffset = self.state.timeZone.scheduleOffset(forDate: Date())
                let beep = self.silencePod ? false : self.beepPreference.shouldBeepForManualCommand
                let _ = try session.resumeBasal(schedule: self.state.basalSchedule, scheduleOffset: scheduleOffset, acknowledgementBeep: beep)
                self.clearSuspendReminder()
                session.dosesForStorage() { (doses) -> Bool in
                    return self.store(doses: doses, in: session)
                }
                completion(nil)
            } catch (let error) {
                completion(error)
            }
        }
    }

    fileprivate func clearSuspendReminder() {
        self.pumpDelegate.notify { (delegate) in
            delegate?.retractAlert(identifier: Alert.Identifier(managerIdentifier: self.managerIdentifier, alertIdentifier: PumpManagerAlert.suspendEnded(triggeringSlot: nil).alertIdentifier))
            delegate?.retractAlert(identifier: Alert.Identifier(managerIdentifier: self.managerIdentifier, alertIdentifier: PumpManagerAlert.suspendEnded(triggeringSlot: nil).repeatingAlertIdentifier))
        }
    }

    public func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }

    public func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }
    
    public func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        let shouldFetchStatus = setStateWithResult { (state) -> Bool? in
            guard state.hasActivePod else {
                return nil // No active pod
            }

            return state.isPumpDataStale
        }

        switch shouldFetchStatus {
        case .none:
            completion?(lastSync)
            return // No active pod
        case true?:
            log.default("Fetching status because pumpData is too old")
            getPodStatus() { (response) in
                completion?(self.lastSync)
            }
        case false?:
            log.default("Skipping status update because pumpData is fresh")
            completion?(self.lastSync)
            silenceAcknowledgedAlerts()
        }
    }


    // MARK: - Programming Delivery

    public func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (PumpManagerError?) -> Void) {
        guard self.hasActivePod else {
            completion(.configuration(OmniBLEPumpManagerError.noPodPaired))
            return
        }

        // Round to nearest supported volume
        let enactUnits = roundToSupportedBolusVolume(units: units)

        let acknowledgementBeep, completionBeep: Bool
        if self.silencePod {
            acknowledgementBeep = false
            completionBeep = false
        } else {
            acknowledgementBeep = self.beepPreference.shouldBeepForCommand(automatic: activationType.isAutomatic)
            completionBeep = beepPreference.shouldBeepForManualCommand && !activationType.isAutomatic
        }

        self.podComms.runSession(withName: "Bolus") { (result) in
            let session: PodCommsSession
            switch result {
            case .success(let s):
                session = s
            case .failure(let error):
                completion(.communication(error))
                return
            }

            defer {
                self.setState({ (state) in
                    state.bolusEngageState = .stable
                })
            }
            self.setState({ (state) in
                state.bolusEngageState = .engaging
            })

            if let podState = self.state.podState, podState.isSuspended || podState.lastDeliveryStatusReceived?.suspended != false {
                self.log.error("enactBolus: returning pod suspended error for bolus")
                completion(.deviceState(PodCommsError.podSuspended))
                return
            }

            // Use bits for the program reminder interval (not used by app)
            //   This trick enables determination, from just the hex messages
            //     of the log file, whether bolus was manually initiated by the
            //     user or automatically initiated by app.
            //   The max possible "reminder" value, 0x3F, would cause the pod to beep
            //      in 63 minutes if bolus had not completed by then.
            let bolusWasAutomaticIndicator: TimeInterval = activationType.isAutomatic ? TimeInterval(minutes: 0x3F) : 0

            let result = session.bolus(units: enactUnits, automatic: activationType.isAutomatic, acknowledgementBeep: acknowledgementBeep, completionBeep: completionBeep, programReminderInterval: bolusWasAutomaticIndicator)

            switch result {
            case .success:
                session.dosesForStorage() { (doses) -> Bool in
                    return self.store(doses: doses, in: session)
                }
                completion(nil)
            case .certainFailure(let error):
                self.log.error("enactBolus failed: %{public}@", String(describing: error))
                completion(.communication(error))
            case .unacknowledged:
                completion(.uncertainDelivery)
            }
        }
    }

    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        guard self.hasActivePod else {
            completion(.failure(.deviceState(OmniBLEPumpManagerError.noPodPaired)))
            return
        }

        guard state.podState?.setupProgress == .completed else {
            // A cancel delivery command before pod setup is complete will fault the pod
            completion(.failure(PumpManagerError.deviceState(PodCommsError.setupNotComplete)))
            return
        }

        self.podComms.runSession(withName: "Cancel Bolus") { (result) in

            let session: PodCommsSession
            switch result {
            case .success(let s):
                session = s
            case .failure(let error):
                completion(.failure(.communication(error)))
                return
            }

            do {
                defer {
                    self.setState({ (state) in
                        state.bolusEngageState = .stable
                    })
                }
                self.setState({ (state) in
                    state.bolusEngageState = .disengaging
                })

                if let bolus = self.state.podState?.unfinalizedBolus, !bolus.isFinished(), bolus.scheduledCertainty == .uncertain {
                    let status = try session.getStatus()

                    if !status.deliveryStatus.bolusing {
                        completion(.success(nil))
                        return
                    }
                }

                // when cancelling a bolus use the built-in type 6 beeeeeep to match PDM if confirmation beeps are enabled
                let beepType: BeepType = self.beepPreference.shouldBeepForManualCommand && !self.silencePod ? .beeeeeep : .noBeepCancel
                let result = session.cancelDelivery(deliveryType: .bolus, beepType: beepType)
                switch result {
                case .certainFailure(let error):
                    throw error
                case .unacknowledged(let error):
                    throw error
                case .success(_, let canceledBolus):
                    session.dosesForStorage() { (doses) -> Bool in
                        return self.store(doses: doses, in: session)
                    }

                    let canceledDoseEntry: DoseEntry? = canceledBolus != nil ? DoseEntry(canceledBolus!) : nil
                    completion(.success(canceledDoseEntry))
                }
            } catch {
                completion(.failure(.communication(error as? LocalizedError)))
            }
        }
    }

    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (PumpManagerError?) -> Void) {
        runTemporaryBasalProgram(unitsPerHour: unitsPerHour, for: duration, automatic: true, completion: completion)
    }

    public func runTemporaryBasalProgram(unitsPerHour: Double, for duration: TimeInterval, automatic: Bool, completion: @escaping (PumpManagerError?) -> Void) {

        guard self.hasActivePod, let podState = self.state.podState else {
            completion(.configuration(OmniBLEPumpManagerError.noPodPaired))
            return
        }

        guard state.podState?.setupProgress == .completed else {
            // A cancel delivery command before pod setup is complete will fault the pod
            completion(.deviceState(PodCommsError.setupNotComplete))
            return
        }

        // Legal duration values are [virtual] zero (to cancel current temp basal) or between 30 min and 12 hours
        guard duration < .ulpOfOne || (duration >= .minutes(30) && duration <= .hours(12)) else {
            completion(.deviceState(OmniBLEPumpManagerError.invalidSetting))
            return
        }

        // Round to nearest supported rate
        let rate = roundToSupportedBasalRate(unitsPerHour: unitsPerHour)

        let acknowledgementBeep, completionBeep: Bool
        if self.silencePod {
            acknowledgementBeep = false
            completionBeep = false
        } else {
            acknowledgementBeep = beepPreference.shouldBeepForCommand(automatic: automatic)
            completionBeep = beepPreference.shouldBeepForManualCommand && !automatic
        }

        self.podComms.runSession(withName: "Enact Temp Basal") { (result) in
            self.log.info("Enact temp basal %.03fU/hr for %ds", rate, Int(duration))
            let session: PodCommsSession
            switch result {
            case .success(let s):
                session = s
            case .failure(let error):
                completion(.communication(error))
                return
            }

            if let podState = self.state.podState, podState.isSuspended || podState.lastDeliveryStatusReceived?.suspended != false {
                self.log.info("Not enacting temp basal because podState indicates pod is suspended.")
                completion(.deviceState(PodCommsError.podSuspended))
                return
            }

            // A resume scheduled basal delivery request is denoted by a 0 duration that cancels any existing temp basal.
            let resumingScheduledBasal = duration < .ulpOfOne

            // If a bolus is not finished, fail if not resuming the scheduled basal
            guard podState.unfinalizedBolus?.isFinished() != false || resumingScheduledBasal else {
                self.log.info("Not enacting temp basal because podState indicates unfinalized bolus in progress.")
                completion(.deviceState(PodCommsError.unfinalizedBolus))
                return
            }

            // Do the safe cancel TB command when resuming scheduled basal delivery OR if unfinalizedTempBasal indicates a
            // running a temp basal OR if we don't have the last pod delivery status confirming that no temp basal is running.
            if resumingScheduledBasal || podState.unfinalizedTempBasal != nil ||
                podState.lastDeliveryStatusReceived == nil || podState.lastDeliveryStatusReceived!.tempBasalRunning
            {
                let status: StatusResponse

                // if resuming scheduled basal delivery & an acknowledgement beep is needed, use the cancel TB beep
                let beepType: BeepType = resumingScheduledBasal && acknowledgementBeep ? .beep : .noBeepCancel
                let result = session.cancelDelivery(deliveryType: .tempBasal, beepType: beepType)
                switch result {
                case .certainFailure(let error):
                    completion(.communication(error))
                    return
                case .unacknowledged(let error):
                    completion(.communication(error))
                    return
                case .success(let cancelTempStatus, _):
                    status = cancelTempStatus
                }

                // If pod is bolusing, fail if not resuming the scheduled basal
                guard !status.deliveryStatus.bolusing || resumingScheduledBasal else {
                    self.log.info("Canceling temp basal because status return indicates bolus in progress.")
                    completion(.communication(PodCommsError.unfinalizedBolus))
                    return
                }

                guard status.deliveryStatus != .suspended else {
                    self.log.info("Canceling temp basal because status return indicates pod is suspended!")
                    completion(.communication(PodCommsError.podSuspended))
                    return
                }
            } else {
                self.log.info("Skipped Cancel TB command before enacting temp basal")
            }

            defer {
                self.setState({ (state) in
                    state.tempBasalEngageState = .stable
                })
            }

            if resumingScheduledBasal {
                self.setState({ (state) in
                    state.tempBasalEngageState = .disengaging
                })
                session.dosesForStorage() { (doses) -> Bool in
                    return self.store(doses: doses, in: session)
                }
                completion(nil)
            } else {
                self.setState({ (state) in
                    state.tempBasalEngageState = .engaging
                })

                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = self.state.timeZone
                let scheduledRate = self.state.basalSchedule.currentRate(using: calendar, at: self.dateGenerator())
                let isHighTemp = rate > scheduledRate

                let result = session.setTempBasal(rate: rate, duration: duration, isHighTemp: isHighTemp, automatic: automatic, acknowledgementBeep: acknowledgementBeep, completionBeep: completionBeep)
                switch result {
                case .success:
                    session.dosesForStorage() { (doses) -> Bool in
                        return self.store(doses: doses, in: session)
                    }
                    completion(nil)
                case .unacknowledged(let error):
                    self.log.error("Temp basal uncertain error: %@", String(describing: error))
                    completion(nil)
                case .certainFailure(let error):
                    self.log.error("setTempBasal failed: %{public}@", String(describing: error))
                    completion(.communication(error))
                }
            }
        }
    }

    /// Returns a dose estimator for the current bolus, if one is in progress
    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        if case .inProgress(let dose) = bolusState(for: self.state) {
            return PodDoseProgressEstimator(dose: dose, pumpManager: self, reportingQueue: dispatchQueue)
        }
        return nil
    }

    public func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>], completion: @escaping (Result<BasalRateSchedule, Error>) -> Void) {
        let newSchedule = BasalSchedule(repeatingScheduleValues: scheduleItems)
        setBasalSchedule(newSchedule) { (error) in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(BasalRateSchedule(dailyItems: scheduleItems, timeZone: self.state.timeZone)!))
            }
        }
    }

    public func syncDeliveryLimits(limits deliveryLimits: DeliveryLimits, completion: @escaping (Result<DeliveryLimits, Error>) -> Void) {
        setState { state in
            if let rate = deliveryLimits.maximumBasalRate?.doubleValue(for: .internationalUnitsPerHour) {
                state.maximumTempBasalRate = rate
                completion(.success(deliveryLimits))
            } else {
                completion(.failure(OmniBLEPumpManagerError.invalidSetting))
            }
        }
    }

    // MARK: - Alerts

    public var isClockOffset: Bool {
        let now = dateGenerator()
        return TimeZone.current.secondsFromGMT(for: now) != state.timeZone.secondsFromGMT(for: now)
    }

    func checkForTimeOffsetChange() {
        let isAlertActive = state.activeAlerts.contains(.timeOffsetChangeDetected)

        if !isAlertActive && isClockOffset && !state.acknowledgedTimeOffsetAlert {
            issueAlert(alert: .timeOffsetChangeDetected)
        } else if isAlertActive && !isClockOffset {
            retractAlert(alert: .timeOffsetChangeDetected)
        }
    }

    public func updateExpirationReminder(_ intervalBeforeExpiration: TimeInterval?, completion: @escaping (OmniBLEPumpManagerError?) -> Void) {

        guard self.hasActivePod, let podState = state.podState, let expiresAt = podState.expiresAt else {
            completion(OmniBLEPumpManagerError.noPodPaired)
            return
        }

        self.podComms.runSession(withName: "Update Expiration Reminder") { (result) in

            let session: PodCommsSession
            switch result {
            case .success(let s):
                session = s
            case .failure(let error):
                completion(.communication(error))
                return
            }

            let podTime = self.podTime
            var expirationReminderPodTime: TimeInterval = 0 // default to expiration reminder alert inactive

            // If the interval before expiration is not a positive value (e.g., it's in the past),
            // then the pod alert will get the default alert time of 0 making this alert inactive.
            if let intervalBeforeExpiration = intervalBeforeExpiration, intervalBeforeExpiration > 0 {
                let timeUntilReminder = expiresAt.addingTimeInterval(-intervalBeforeExpiration).timeIntervalSince(self.dateGenerator())
                // Only bother to set an expiration reminder pod alert if it is still at least a couple of minutes in the future
                if timeUntilReminder > .minutes(2) {
                    expirationReminderPodTime = podTime + timeUntilReminder
                    self.log.debug("Update Expiration timeUntilReminder=%@, podTime=%@, expirationReminderPodTime=%@", timeUntilReminder.timeIntervalStr, podTime.timeIntervalStr, expirationReminderPodTime.timeIntervalStr)
                }
            }

            let expirationReminder = PodAlert.expirationReminder(offset: podTime, absAlertTime: expirationReminderPodTime, silent: self.silencePod)
            do {
                let beepBlock = self.beepMessageBlock(beepType: .beep)
                try session.configureAlerts([expirationReminder], beepBlock: beepBlock)
                self.setState({ (state) in
                    state.scheduledExpirationReminderOffset = intervalBeforeExpiration
                })
                completion(nil)
            } catch {
                completion(.communication(error))
                return
            }
        }
    }

    public var allowedExpirationReminderDates: [Date]? {
        guard let expiration = state.podState?.expiresAt else {
            return nil
        }

        let allDates = Array(stride(
            from: -Pod.expirationReminderAlertMaxHoursBeforeExpiration,
            through: -Pod.expirationReminderAlertMinHoursBeforeExpiration,
            by: 1)).map
        { (i: Int) -> Date in
            expiration.addingTimeInterval(.hours(Double(i)))
        }
        let now = dateGenerator()
        // Have a couple minutes of slop to avoid confusion trying to set an expiration reminder too close to now
        return allDates.filter { $0.timeIntervalSince(now) > .minutes(2) }
    }

    public var scheduledExpirationReminder: Date? {
        guard let expiration = state.podState?.expiresAt, let offset = state.scheduledExpirationReminderOffset, offset > 0 else {
            return nil
        }

        // It is possible the scheduledExpirationReminderOffset does not fall on the hour, but instead be a few seconds off
        // since the allowedExpirationReminderDates are by the hour, force the offset to be on the hour
        return expiration.addingTimeInterval(-.hours(round(offset.hours)))
    }

    // Updates the low reservior reminder value both for the current pod (when applicable) and for future pods
    public func updateLowReservoirReminder(_ value: Int, completion: @escaping (OmniBLEPumpManagerError?) -> Void) {

        let supportedValue = min(max(0, Double(value)), Pod.maximumReservoirReading)
        let setLowReservoirReminderValue = {
            self.log.default("Set Low Reservoir Reminder to %d U", value)
            self.lowReservoirReminderValue = supportedValue
            completion(nil)
        }

        guard self.hasActivePod else {
            // no active pod, just set the internal state for the next pod
            setLowReservoirReminderValue()
            return
        }

        guard let currentReservoirLevel = self.reservoirLevel?.rawValue, currentReservoirLevel > supportedValue else {
            // Since the new low reservoir alert level is not below the current reservoir value,
            // just set the internal state for the next pod to prevent an immediate low reservoir alert.
            setLowReservoirReminderValue()
            return
        }

        self.podComms.runSession(withName: "Program Low Reservoir Reminder") { (result) in

            let session: PodCommsSession
            switch result {
            case .success(let s):
                session = s
            case .failure(let error):
                completion(.communication(error))
                return
            }

            let lowReservoirReminder = PodAlert.lowReservoir(units: supportedValue, silent: self.silencePod)
            do {
                let beepBlock = self.beepMessageBlock(beepType: .beep)
                try session.configureAlerts([lowReservoirReminder], beepBlock: beepBlock)
                self.lowReservoirReminderValue = supportedValue
                completion(nil)
            } catch {
                completion(.communication(error))
                return
            }
        }
    }

    func issueAlert(alert: PumpManagerAlert) {
        let identifier = Alert.Identifier(managerIdentifier: self.managerIdentifier, alertIdentifier: alert.alertIdentifier)
        let loopAlert = Alert(identifier: identifier, foregroundContent: alert.foregroundContent, backgroundContent: alert.backgroundContent, trigger: .immediate)
        pumpDelegate.notify { (delegate) in
            delegate?.issueAlert(loopAlert)
        }

        if let repeatInterval = alert.repeatInterval {
            // Schedule an additional repeating 15 minute reminder for suspend period ended.
            let repeatingIdentifier = Alert.Identifier(managerIdentifier: self.managerIdentifier, alertIdentifier: alert.repeatingAlertIdentifier)
            let loopAlert = Alert(identifier: repeatingIdentifier, foregroundContent: alert.foregroundContent, backgroundContent: alert.backgroundContent, trigger: .repeating(repeatInterval: repeatInterval))
            pumpDelegate.notify { (delegate) in
                delegate?.issueAlert(loopAlert)
            }
        }

        self.setState { (state) in
            state.activeAlerts.insert(alert)
        }
    }

    func retractAlert(alert: PumpManagerAlert) {
        let identifier = Alert.Identifier(managerIdentifier: self.managerIdentifier, alertIdentifier: alert.alertIdentifier)
        pumpDelegate.notify { (delegate) in
            delegate?.retractAlert(identifier: identifier)
        }
        if alert.isRepeating {
            let repeatingIdentifier = Alert.Identifier(managerIdentifier: self.managerIdentifier, alertIdentifier: alert.repeatingAlertIdentifier)
            pumpDelegate.notify { (delegate) in
                delegate?.retractAlert(identifier: repeatingIdentifier)
            }
        }
        self.setState { (state) in
            state.activeAlerts.remove(alert)
        }
    }

    private func alertsChanged(oldAlerts: AlertSet, newAlerts: AlertSet) {
        guard let podState = state.podState else {
            preconditionFailure("trying to manage alerts without podState")
        }

        let (added, removed) = oldAlerts.compare(to: newAlerts)
        for slot in added {
            if let podAlert = podState.configuredAlerts[slot] {
                log.default("Alert slot triggered: %{public}@", String(describing: slot))
                if let pumpManagerAlert = getPumpManagerAlert(for: podAlert, slot: slot) {
                    issueAlert(alert: pumpManagerAlert)
                } else {
                    log.default("Ignoring alert: %{public}@", String(describing: podAlert))
                }
            } else {
                log.error("Unconfigured alert slot triggered: %{public}@", String(describing: slot))
                let pumpManagerAlert = PumpManagerAlert.unexpectedAlert(triggeringSlot: slot)
                issueAlert(alert: pumpManagerAlert)
            }
        }
        for alert in removed {
            log.default("Alert slot cleared: %{public}@", String(describing: alert))
        }
    }

    private func getPumpManagerAlert(for podAlert: PodAlert, slot: AlertSlot) -> PumpManagerAlert? {

        switch podAlert {
        case .shutdownImminent:
            return PumpManagerAlert.podExpireImminent(triggeringSlot: slot)
        case .expirationReminder:
            guard let podState = state.podState, let expiresAt = podState.expiresAt else {
                preconditionFailure("trying to lookup expiresAt")
            }
            let timeToExpiry = TimeInterval(hours: expiresAt.timeIntervalSince(dateGenerator()).hours.rounded())
            return PumpManagerAlert.userPodExpiration(triggeringSlot: slot, scheduledExpirationReminderOffset: timeToExpiry)
        case .lowReservoir(let units, _):
            return PumpManagerAlert.lowReservoir(triggeringSlot: slot, lowReservoirReminderValue: units)
        case .suspendTimeExpired:
            return PumpManagerAlert.suspendEnded(triggeringSlot: slot)
        case .expired:
            return PumpManagerAlert.podExpiring(triggeringSlot: slot)
        default:
            // No PumpManagerAlerts are used for any other pod alerts (including suspendInProgress).
            return nil
        }
    }

    private func silenceAcknowledgedAlerts() {
        // Only attempt to clear one per cycle (more than one should be rare)
        if let alert = state.alertsWithPendingAcknowledgment.first {
            if let slot = alert.triggeringSlot {
                self.podComms.runSession(withName: "Silence already acknowledged alert") { (result) in
                    switch result {
                    case .success(let session):
                        do {
                            let _ = try session.acknowledgeAlerts(alerts: AlertSet(slots: [slot]))
                        } catch {
                            return
                        }
                        self.setState { state in
                            state.activeAlerts.remove(alert)
                            state.alertsWithPendingAcknowledgment.remove(alert)
                        }
                    case .failure:
                        return
                    }
                }
            }
        }
    }

    private func notifyPodFault(fault: DetailedStatus) {
        pumpDelegate.notify { delegate in
            let content = Alert.Content(title: fault.faultEventCode.notificationTitle,
                                        body: fault.faultEventCode.notificationBody,
                                        acknowledgeActionButtonLabel: LocalizedString("OK", comment: "Alert acknowledgment OK button"))
            delegate?.issueAlert(Alert(identifier: Alert.Identifier(managerIdentifier: OmniBLEPumpManager.podAlarmNotificationIdentifier,
                                                                    alertIdentifier: fault.faultEventCode.description),
                                       foregroundContent: content, backgroundContent: content,
                                       trigger: .immediate))
        }
    }

    // MARK: - Reporting Doses

    // This cannot be called from within the lockedState lock!
    func store(doses: [UnfinalizedDose], in session: PodCommsSession) -> Bool {
        session.assertOnSessionQueue()

        // We block the session until the data's confirmed stored by the delegate
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        store(doses: doses) { (error) in
            success = (error == nil)
            semaphore.signal()
        }

        semaphore.wait()

        if success {
            setState { (state) in
                state.lastPumpDataReportDate = Date()
            }
        }
        return success
    }

    func store(doses: [UnfinalizedDose], completion: @escaping (_ error: Error?) -> Void) {
        let lastSync = lastSync

        pumpDelegate.notify { (delegate) in
            guard let delegate = delegate else {
                preconditionFailure("pumpManagerDelegate cannot be nil")
            }


            delegate.pumpManager(self, hasNewPumpEvents: doses.map { NewPumpEvent($0) }, lastReconciliation: lastSync, completion: { (error) in
                if let error = error {
                    self.log.error("Error storing pod events: %@", String(describing: error))
                } else {
                    self.log.info("DU: Stored pod events: %@", String(describing: doses))
                }

                completion(error)
            })
        }
    }
}

extension OmniBLEPumpManager: MessageLogger {
    func didSend(_ message: Data) {
        log.default("didSend: %{public}@", message.hexadecimalString)
        self.logDeviceCommunication(message.hexadecimalString, type: .send)
    }

    func didReceive(_ message: Data) {
        log.default("didReceive: %{public}@", message.hexadecimalString)
        self.logDeviceCommunication(message.hexadecimalString, type: .receive)
    }

    func didError(_ message: String) {
        self.logDeviceCommunication(message, type: .error)
    }
}

extension OmniBLEPumpManager: PodCommsDelegate {

    func podCommsDidEstablishSession(_ podComms: PodComms) {

        podComms.runSession(withName: "Post-connect status fetch") { result in
            switch result {
            case .success(let session):
                let _ = try? session.getStatus()
                self.silenceAcknowledgedAlerts()
                session.dosesForStorage() { (doses) -> Bool in
                    return self.store(doses: doses, in: session)
                }
                self.issueHeartbeatIfNeeded()
            case .failure:
                // Errors can be ignored here.
                break
            }
        }
        
    }

    func podComms(_ podComms: PodComms, didChange podState: PodState?) {
        if let podState = podState {
            let (newFault, oldAlerts, newAlerts) = setStateWithResult { (state) -> (DetailedStatus?,AlertSet,AlertSet) in
                if (state.suspendEngageState == .engaging && podState.isSuspended) ||
                   (state.suspendEngageState == .disengaging && !podState.isSuspended)
                {
                    state.suspendEngageState = .stable
                }

                let newFault: DetailedStatus?

                // Check for new fault state
                if state.podState?.fault == nil, let fault = podState.fault {
                    newFault = fault
                } else {
                    newFault = nil
                }

                let oldAlerts: AlertSet = state.podState?.activeAlertSlots ?? AlertSet.none
                let newAlerts: AlertSet = podState.activeAlertSlots

                state.updatePodStateFromPodComms(podState)

                return (newFault, oldAlerts, newAlerts)
            }

            if let newFault = newFault {
                notifyPodFault(fault: newFault)
            }

            if oldAlerts != newAlerts {
                self.alertsChanged(oldAlerts: oldAlerts, newAlerts: newAlerts)
            }
        } else {
            // Resetting podState
            setState { state in
                state.updatePodStateFromPodComms(podState)
            }
        }
    }
}

extension OmniBLEPumpManager: AlertSoundVendor {
    public func getSoundBaseURL() -> URL? {
        return nil
    }

    public func getSounds() -> [Alert.Sound] {
        return []
    }
}

// MARK: - AlertResponder implementation
extension OmniBLEPumpManager {
    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        guard self.hasActivePod else {
            completion(OmniBLEPumpManagerError.noPodPaired)
            return
        }

        for alert in state.activeAlerts {
            if alert.alertIdentifier == alertIdentifier || alert.repeatingAlertIdentifier == alertIdentifier {
                // If this alert was triggered by the pod find the slot to clear it.
                if let slot = alert.triggeringSlot {
                    if (self.state.podState?.isSuspended == true || self.state.podState?.lastDeliveryStatusReceived?.suspended == true) &&
                        slot == .slot6SuspendTimeExpired
                    {
                        // Don't clear this pod alert here with the pod still suspended so that the suspend time expired
                        // pod alert beeping will continue until the pod is resumed which will then deactivate this alert.
                        log.default("Skipping acknowledgement of suspend time expired alert with a suspended pod")
                        completion(nil)
                        return
                    }
                    self.podComms.runSession(withName: "Acknowledge Alert") { (result) in
                        switch result {
                        case .success(let session):
                            do {
                                let beepBlock = self.beepMessageBlock(beepType: .beep)
                                let _ = try session.acknowledgeAlerts(alerts: AlertSet(slots: [slot]), beepBlock: beepBlock)
                            } catch {
                                self.setState { state in
                                    state.alertsWithPendingAcknowledgment.insert(alert)
                                }
                                completion(error)
                                return
                            }
                            self.setState { state in
                                state.activeAlerts.remove(alert)
                            }
                            completion(nil)
                        case .failure(let error):
                            self.setState { state in
                                state.alertsWithPendingAcknowledgment.insert(alert)
                            }
                            completion(error)
                        }
                    }
                } else {
                    // Non-pod alert
                    self.setState { state in
                        state.activeAlerts.remove(alert)
                        if alert == .timeOffsetChangeDetected {
                            state.acknowledgedTimeOffsetAlert = true
                        }
                    }
                    completion(nil)
                }
            }
        }
    }
}

extension FaultEventCode {
    public var notificationTitle: String {
        switch self.faultType {
        case .reservoirEmpty:
            return LocalizedString("Empty Reservoir", comment: "The title for Empty Reservoir alarm notification")
        case .occluded, .occlusionCheckStartup1, .occlusionCheckStartup2, .occlusionCheckTimeouts1, .occlusionCheckTimeouts2, .occlusionCheckTimeouts3, .occlusionCheckPulseIssue, .occlusionCheckBolusProblem:
            return LocalizedString("Occlusion Detected", comment: "The title for Occlusion alarm notification")
        case .exceededMaximumPodLife80Hrs:
            return LocalizedString("Pod Expired", comment: "The title for Pod Expired alarm notification")
        default:
            return String(format: LocalizedString("Critical Pod Fault %1$03d", comment: "The title for AlarmCode.other notification: (1: fault code value)"), self.rawValue)
        }
    }

    public var notificationBody: String {
        return LocalizedString("Insulin delivery stopped. Change Pod now.", comment: "The default notification body for AlarmCodes")
    }
}
