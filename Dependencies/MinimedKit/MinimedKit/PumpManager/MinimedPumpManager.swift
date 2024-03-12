//
//  MinimedPumpManager.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import RileyLinkKit
import RileyLinkBLEKit
import os.log

public protocol MinimedPumpManagerStateObserver: AnyObject {
    func didUpdatePumpManagerState(_ state: MinimedPumpManagerState)
}

public class MinimedPumpManager: RileyLinkPumpManager {
    
    public static let pluginIdentifier = "Minimed500"

    // Primarily used for testing
    public let dateGenerator: () -> Date
        
    public init(state: MinimedPumpManagerState, rileyLinkDeviceProvider: RileyLinkDeviceProvider, pumpOps: PumpOps? = nil, dateGenerator: @escaping () -> Date = Date.init) {
        self.lockedState = Locked(state)

        self.dateGenerator = dateGenerator

        self.hkDevice = HKDevice(
            name: MinimedPumpManager.pluginIdentifier,
            manufacturer: "Medtronic",
            model: state.pumpModel.rawValue,
            hardwareVersion: nil,
            firmwareVersion: state.pumpFirmwareVersion,
            softwareVersion: String(MinimedKitVersionNumber),
            localIdentifier: state.pumpID,
            udiDeviceIdentifier: nil
        )
        
        super.init(rileyLinkDeviceProvider: rileyLinkDeviceProvider)

        // Pump communication
        let idleListeningEnabled = state.pumpModel.hasMySentry && state.useMySentry

        self.pumpOps = pumpOps ?? MinimedPumpOps(pumpSettings: state.pumpSettings, pumpState: state.pumpState, delegate: self)

        self.rileyLinkDeviceProvider.idleListeningState = idleListeningEnabled ? MinimedPumpManagerState.idleListeningEnabledDefaults : .disabled
    }

    public required convenience init?(rawState: PumpManager.RawStateValue) {
        guard let state = MinimedPumpManagerState(rawValue: rawState),
            let connectionManagerState = state.rileyLinkConnectionState else
        {
            return nil
        }

        let deviceProvider = RileyLinkBluetoothDeviceProvider(autoConnectIDs: connectionManagerState.autoConnectIDs)

        self.init(state: state, rileyLinkDeviceProvider: deviceProvider)
        
        deviceProvider.delegate = self
    }

    public private(set) var pumpOps: PumpOps!

    // We issue notifications at 30, 20, and 10. Indicators turn warning color at 30.
    public let lowReservoirWarningLevel = 30.0

    // MARK: - PumpManager

    public let stateObservers = WeakSynchronizedSet<MinimedPumpManagerStateObserver>()

    public var state: MinimedPumpManagerState {
        return lockedState.value
    }
    private let lockedState: Locked<MinimedPumpManagerState>
    
    private func setState(_ changes: (_ state: inout MinimedPumpManagerState) -> Void) -> Void {
        return setStateWithResult(changes)
    }
    
    private func mutateState(_ changes: (_ state: inout MinimedPumpManagerState) -> Void) -> MinimedPumpManagerState {
        return setStateWithResult({ (state) -> MinimedPumpManagerState in
            changes(&state)
            return state
        })
    }
    
    private func setStateWithResult<ReturnType>(_ changes: (_ state: inout MinimedPumpManagerState) -> ReturnType) -> ReturnType {
        var oldValue: MinimedPumpManagerState!
        var returnValue: ReturnType!
        let newValue = lockedState.mutate { (state) in
            oldValue = state
            returnValue = changes(&state)
        }
        
        guard oldValue != newValue else {
            return returnValue
        }
        
        let recents = self.recents
        let oldStatus = status(for: oldValue, recents: recents)
        let newStatus = status(for: newValue, recents: recents)

        // PumpManagerStatus may have changed
        if oldStatus != newStatus
        {
            notifyStatusObservers(oldStatus: oldStatus)
        }
        
        pumpDelegate.notify { (delegate) in
            delegate?.pumpManagerDidUpdateState(self)
        }
        stateObservers.forEach { (observer) in
            observer.didUpdatePumpManagerState(newValue)
        }
        return returnValue
    }
    

    /// Temporal state of the manager
    public var recents: MinimedPumpManagerRecents {
        get {
            return lockedRecents.value
        }
        set {
            let oldValue = recents
            let oldStatus = status
            lockedRecents.value = newValue

            // Battery percentage may have changed
            if oldValue.latestPumpStatusFromMySentry != newValue.latestPumpStatusFromMySentry ||
                oldValue.latestPumpStatus != newValue.latestPumpStatus
            {
                let oldBatteryPercentage = state.batteryPercentage
                let newBatteryPercentage: Double?

                // Persist the updated battery level
                if let status = newValue.latestPumpStatusFromMySentry {
                    newBatteryPercentage = Double(status.batteryRemainingPercent) / 100
                } else if let status = newValue.latestPumpStatus {
                    newBatteryPercentage = batteryChemistry.chargeRemaining(at: status.batteryVolts)
                } else {
                    newBatteryPercentage = nil
                }

                self.setState({ (state) in
                    if oldBatteryPercentage != newBatteryPercentage {
                        state.batteryPercentage = newBatteryPercentage
                        checkPumpBattery(oldBatteryPercentage: oldBatteryPercentage, newBatteryPercentage: newBatteryPercentage)
                    }

                    if let status = newValue.latestPumpStatus {
                        if case .resumed = state.suspendState, status.suspended {
                            state.suspendState = .suspended(dateGenerator())
                        }
                        if case .suspended = state.suspendState, !status.suspended {
                            state.suspendState = .resumed(dateGenerator())
                        }
                    }
                })
            }
            if oldStatus != status {
                notifyStatusObservers(oldStatus: oldStatus)
            }
        }
    }
    private let lockedRecents = Locked(MinimedPumpManagerRecents())

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
        // Not dispatching here; if delegate queue is blocked, timestamps will be delayed
        self.pumpDelegate.delegate?.deviceManager(self, logEventForDeviceIdentifier: state.pumpID, type: type, message: message, completion: nil)
    }

    private let cgmDelegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()

    public let log = OSLog(category: "MinimedPumpManager")

    // MARK: - CGMManager

    private let hkDevice: HKDevice

    // MARK: - RileyLink Updates

    override public var rileyLinkConnectionManagerState: RileyLinkConnectionState? {
        get {
            return state.rileyLinkConnectionState
        }
        set {
            setState { (state) in
                state.rileyLinkConnectionState = newValue
            }
        }
    }

    override public func device(_ device: RileyLinkDevice, didReceivePacket packet: RFPacket) {
        device.assertOnSessionQueue()

        guard let data = MinimedPacket(encodedData: packet.data)?.data,
            let message = PumpMessage(rxData: data),
            message.address.hexadecimalString == state.pumpID,
            case .mySentry = message.packetType
        else {
            return
        }

        logDeviceCommunication("MySentry \(String(describing: message))", type: .receive)

        switch message.messageBody {
        case let body as MySentryPumpStatusMessageBody:
            self.updatePumpStatus(body, from: device)
        case let body as MySentryAlertMessageBody:
            self.log.default("MySentry Alert: %{public}@", String(describing: body))
        case let body as MySentryAlertClearedMessageBody:
            self.log.default("MySentry Alert Cleared: %{public}@", String(describing: body))
            break
        default:
            self.log.error("Unknown MySentry Message: %d: %{public}@", message.messageType.rawValue, message.txData.hexadecimalString)
        }
    }

    override public func deviceTimerDidTick(_ device: RileyLinkDevice) {
        pumpDelegate.notify { (delegate) in
            delegate?.pumpManagerBLEHeartbeatDidFire(self)
        }
    }
    
    public var rileyLinkBatteryAlertLevel: Int? {
        get {
            return state.rileyLinkBatteryAlertLevel
        }
        set {
            setState { state in
                state.rileyLinkBatteryAlertLevel = newValue
            }
        }
    }
    
    public override func device(_ device: RileyLinkDevice, didUpdateBattery level: Int) {
        let repeatInterval: TimeInterval = .hours(1)
        
        if let alertLevel = state.rileyLinkBatteryAlertLevel,
           level <= alertLevel,
           state.lastRileyLinkBatteryAlertDate.addingTimeInterval(repeatInterval) < dateGenerator()
        {
            self.setState { state in
                state.lastRileyLinkBatteryAlertDate = dateGenerator()
            }
            self.pumpDelegate.notify { delegate in
                let identifier = Alert.Identifier(managerIdentifier: self.pluginIdentifier, alertIdentifier: "lowRLBattery")
                let alertBody = String(format: LocalizedString("\"%1$@\" has a low battery", comment: "Format string for low battery alert body for RileyLink. (1: device name)"), device.name ?? "unnamed")
                let content = Alert.Content(title: LocalizedString("Low RileyLink Battery", comment: "Title for RileyLink low battery alert"), body: alertBody, acknowledgeActionButtonLabel: LocalizedString("OK", comment: "Acknowledge button label for RileyLink low battery alert"))
                delegate?.issueAlert(Alert(identifier: identifier, foregroundContent: content, backgroundContent: content, trigger: .immediate))
            }
        }
    }

    // MARK: - CustomDebugStringConvertible

    override public var debugDescription: String {
        return [
            "## MinimedPumpManager",
            "isPumpDataStale: \(isPumpDataStale)",
            "pumpOps: \(String(reflecting: pumpOps))",
            "recents: \(String(reflecting: recents))",
            "state: \(String(reflecting: state))",
            "status: \(String(describing: status))",
            "stateObservers.count: \(stateObservers.cleanupDeallocatedElements().count)",
            "statusObservers.count: \(statusObservers.cleanupDeallocatedElements().count)",
            super.debugDescription,
        ].joined(separator: "\n")
    }
}

extension MinimedPumpManager {
    /**
     Attempts to fix an extended communication failure between a RileyLink device and the pump

     - parameter device: The RileyLink device
     */
    private func troubleshootPumpComms(using device: RileyLinkDevice) {
        device.assertOnSessionQueue()

        // Ensuring timer tick is enabled will allow more tries to bring the pump data up-to-date.
        updateBLEHeartbeatPreference()

        // How long we should wait before we re-tune the RileyLink
        let tuneTolerance = TimeInterval(minutes: 14)

        let lastTuned = state.lastTuned ?? .distantPast

        if lastTuned.timeIntervalSinceNow <= -tuneTolerance {
            pumpOps.runSession(withName: "Tune pump", using: device) { (session) in
                do {
                    let scanResult = try session.tuneRadio(attempts: 1)
                    self.log.default("Device %{public}@ auto-tuned to %{public}@ MHz", device.name ?? "", String(describing: scanResult.bestFrequency))
                } catch let error {
                    self.log.error("Device %{public}@ auto-tune failed with error: %{public}@", device.name ?? "", String(describing: error))
                    self.rileyLinkDeviceProvider.deprioritize(device, completion: nil)
                    if let error = error as? LocalizedError {
                        self.pumpDelegate.notify { (delegate) in
                            delegate?.pumpManager(self, didError: PumpManagerError.communication(MinimedPumpManagerError.tuneFailed(error)))
                        }
                    }
                }
            }
        } else {
            rileyLinkDeviceProvider.deprioritize(device, completion: nil)
        }
    }

    /// - Throws: `PumpCommandError` specifying the failure sequence
    private func runSuspendResumeOnSession(suspendResumeState: SuspendResumeMessageBody.SuspendResumeState, session: PumpOpsSession, insulinType: InsulinType) throws {
        
        defer { self.recents.suspendEngageState = .stable }
        self.recents.suspendEngageState = suspendResumeState == .suspend ? .engaging : .disengaging

        try session.setSuspendResumeState(suspendResumeState)
        
        setState { (state) in
            let date = dateGenerator()
            switch suspendResumeState {
            case .suspend:
                state.suspendState = .suspended(date)
            case .resume:
                state.suspendState = .resumed(date)
            }
            
            if suspendResumeState == .suspend {
                let pumpModel = state.pumpModel
                state.unfinalizedBolus?.cancel(at: dateGenerator(), pumpModel: pumpModel)
                if let bolus = state.unfinalizedBolus {
                    state.pendingDoses.append(bolus)
                }
                state.unfinalizedBolus = nil
                
                state.pendingDoses.append(UnfinalizedDose(suspendStartTime: dateGenerator()))
            } else {
                state.pendingDoses.append(UnfinalizedDose(resumeStartTime: dateGenerator(), insulinType: insulinType))
            }
        }
    }

    private func setSuspendResumeState(state: SuspendResumeMessageBody.SuspendResumeState, insulinType: InsulinType, completion: @escaping (MinimedPumpManagerError?) -> Void) {
        rileyLinkDeviceProvider.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                completion(MinimedPumpManagerError.noRileyLink)
                return
            }
            
            let sessionName: String = {
                switch state {
                case .suspend:
                    return "Suspend Delivery"
                case .resume:
                    return "Resume Delivery"
                }
            }()

            self.pumpOps.runSession(withName: sessionName, using: device) { (session) in
                do {
                    try self.runSuspendResumeOnSession(suspendResumeState: state, session: session, insulinType: insulinType)
                    self.storePendingPumpEvents({ (error) in
                        completion(error)
                    })
                } catch let error {
                    self.troubleshootPumpComms(using: device)
                    completion(MinimedPumpManagerError.commsError(error as! PumpCommandError))
                }
            }
        }
    }

    /**
     Handles receiving a MySentry status message, which are only posted by MM x23 pumps.

     This message has two important pieces of info about the pump: reservoir volume and battery.

     Because the RileyLink must actively listen for these packets, they are not a reliable heartbeat. However, we can still use them to assert glucose data is current.

     - parameter status: The status message body
     - parameter device: The RileyLink that received the message
     */
    private func updatePumpStatus(_ status: MySentryPumpStatusMessageBody, from device: RileyLinkDevice) {
        device.assertOnSessionQueue()

        log.default("MySentry message received")

        var pumpDateComponents = status.pumpDateComponents
        var glucoseDateComponents = status.glucoseDateComponents

        let timeZone = state.timeZone
        pumpDateComponents.timeZone = timeZone
        glucoseDateComponents?.timeZone = timeZone
        
        checkRileyLinkBattery()

        // The pump sends the same message 3x, so ignore it if we've already seen it.
        guard status != recents.latestPumpStatusFromMySentry, let pumpDate = pumpDateComponents.date else {
            return
        }

        // Ignore status messages without some semblance of recency.
        guard abs(pumpDate.timeIntervalSinceNow) < .minutes(5) else {
            log.error("Ignored MySentry status due to date mismatch: %{public}@ in %{public}", String(describing: pumpDate), String(describing: timeZone))
            return
        }
        
        recents.latestPumpStatusFromMySentry = status

        switch status.glucose {
        case .active(glucose: let glucose):
            // Enlite data is included
            if let date = glucoseDateComponents?.date {
                let sample = NewGlucoseSample(
                    date: date,
                    quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucose)),
                    condition: nil,
                    trend: status.glucoseTrend.loopKitGlucoseTrend,
                    trendRate: nil,
                    isDisplayOnly: false,
                    wasUserEntered: false,
                    syncIdentifier: status.glucoseSyncIdentifier ?? UUID().uuidString,
                    device: self.device
                )

                cgmDelegate.notify { (delegate) in
                    delegate?.cgmManager(self, hasNew: .newData([sample]))
                }
            }
        case .off:
            // Enlite is disabled, so assert glucose from another source
            pumpDelegate.notify { (delegate) in
                delegate?.pumpManagerBLEHeartbeatDidFire(self)
            }
        default:
            // Anything else is an Enlite error
            // TODO: Provide info about status.glucose
            cgmDelegate.notify { (delegate) in
                delegate?.cgmManager(self, hasNew: .error(PumpManagerError.deviceState(nil)))
            }
        }
        
        // Sentry packets are sent in groups of 3, 5s apart. Wait 11s before allowing the loop data to continue to avoid conflicting comms.
        device.sessionQueueAsyncAfter(deadline: .now() + .seconds(11)) { [weak self] in
            self?.refreshPumpData { _ in }
        }
    }

    public func buildPumpStatusHighlight(for state: MinimedPumpManagerState, recents: MinimedPumpManagerRecents, andDate date: Date) -> PumpStatusHighlight? {

        if case .suspended = state.suspendState {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString("Insulin Suspended", comment: "Status highlight that insulin delivery was suspended."),
                imageName: "pause.circle.fill",
                state: .warning)
        }
        
        if date.timeIntervalSince(lastSync(for: state, recents: recents) ?? .distantPast) > .minutes(12) {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString("Signal Loss", comment: "Status highlight when communications with the pod haven't happened recently."),
                imageName: "exclamationmark.circle.fill",
                state: .critical)
        }
        return nil
    }

    
    private func checkRileyLinkBattery() {
        rileyLinkDeviceProvider.getDevices { devices in
            for device in devices {
                device.updateBatteryLevel()
            }
        }
    }
    
    private static var pumpBatteryLowAlertIdentifier: Alert.Identifier {
        return Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: "PumpBatteryLow")
    }

    private var pumpBatteryLowAlert: Alert {
        let title = LocalizedString("Pump Battery Low", comment: "The notification title for a low pump battery")
        let body = LocalizedString("Change the pump battery immediately", comment: "The notification alert describing a low pump battery")
        let content = Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: LocalizedString("Dismiss", comment: "Default alert dismissal"))
        return Alert(identifier: Self.pumpBatteryLowAlertIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate)
    }
    
    private var batteryReplacementDetectionThreshold: Double { 0.5 }

    private func checkPumpBattery(oldBatteryPercentage: Double?, newBatteryPercentage: Double?) {
        guard let newBatteryPercentage = newBatteryPercentage else {
            return
        }
        if oldBatteryPercentage != newBatteryPercentage, newBatteryPercentage == 0 {
            pumpDelegate.notify { (delegate) in
                delegate?.issueAlert(self.pumpBatteryLowAlert)
            }
        }
        
        if let oldBatteryPercentage = oldBatteryPercentage, newBatteryPercentage - oldBatteryPercentage >= batteryReplacementDetectionThreshold {
            pumpDelegate.notify { (delegate) in
                delegate?.retractAlert(identifier: Self.pumpBatteryLowAlertIdentifier)
            }
        }
    }
    
    /**
     Store a new reservoir volume and notify observers of new pump data.

     - parameter units:    The number of units remaining
     - parameter date:     The date the reservoir was read
     - parameter completion: completion handler
     */
    private func updateReservoirVolume(_ units: Double, at date: Date, completion: @escaping (Result<Bool, Error>) -> Void) {
        // Must be called from the sessionQueue

        setState { (state) in
            state.lastReservoirReading = ReservoirReading(units: units, validAt: date)
        }

        pumpDelegate.notify { (delegate) in
            delegate?.pumpManager(self, didReadReservoirValue: units, at: date) { (result) in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                    break
                case .success(let (newValue, lastValue, areStoredValuesContinuous)):
                    self.evaluateReservoirAlerts(lastValue: lastValue, newValue: newValue, areStoredValuesContinuous: areStoredValuesContinuous)

                    if areStoredValuesContinuous {
                        self.recents.lastContinuousReservoir = date
                    }
                    completion(.success(areStoredValuesContinuous))
                }
            }
        }

        // New reservoir data means we may want to adjust our timer tick requirements
        updateBLEHeartbeatPreference()
    }

    private static var pumpReservoirEmptyAlertIdentifier: Alert.Identifier {
        return Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: "PumpReservoirEmpty")
    }

    private var pumpReservoirEmptyAlert: Alert {
        let title = LocalizedString("Pump Reservoir Empty", comment: "The notification title for an empty pump reservoir")
        let body = LocalizedString("Change the pump reservoir now", comment: "The notification alert describing an empty pump reservoir")
        let content = Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: LocalizedString("Ok", comment: "Default alert dismissal"))
        return Alert(identifier: Self.pumpReservoirEmptyAlertIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate)
    }

    private static var pumpReservoirLowAlertIdentifier: Alert.Identifier {
        return Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: "PumpReservoirLow")
    }

    private func pumpReservoirLowAlertForAmount(_ units: Double, andTimeRemaining remaining: TimeInterval?) -> Alert {
        let title = LocalizedString("Pump Reservoir Low", comment: "The notification title for a low pump reservoir")

        let unitsString = NumberFormatter.localizedString(from: NSNumber(value: units), number: .decimal)

        let intervalFormatter = DateComponentsFormatter()
        intervalFormatter.allowedUnits = [.hour, .minute]
        intervalFormatter.maximumUnitCount = 1
        intervalFormatter.unitsStyle = .full
        intervalFormatter.includesApproximationPhrase = true
        intervalFormatter.includesTimeRemainingPhrase = true

        let body: String

        if let remaining = remaining, let timeString = intervalFormatter.string(from: remaining) {
            body = String(format: LocalizedString("%1$@ U left: %2$@", comment: "Low reservoir alert with time remaining format string. (1: Number of units remaining)(2: approximate time remaining)"), unitsString, timeString)
        } else {
            body = String(format: LocalizedString("%1$@ U left", comment: "Low reservoir alert format string. (1: Number of units remaining)"), unitsString)
        }

        let content = Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: LocalizedString("Ok", comment: "Default alert dismissal"))
        return Alert(identifier: Self.pumpReservoirLowAlertIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate)
    }

    private func evaluateReservoirAlerts(lastValue: ReservoirValue?, newValue: ReservoirValue, areStoredValuesContinuous: Bool) {
        // Send notifications for low reservoir if necessary
        if let previousVolume = lastValue?.unitVolume {
            guard newValue.unitVolume > 0 else {
                pumpDelegate.notify { (delegate) in
                    delegate?.issueAlert(self.pumpReservoirEmptyAlert)
                }
                return
            }

            let warningThresholds: [Double] = [10, 20, lowReservoirWarningLevel]

            for threshold in warningThresholds {
                if newValue.unitVolume <= threshold && previousVolume > threshold {
                    pumpDelegate.notify { (delegate) in
                        delegate?.issueAlert(self.pumpReservoirLowAlertForAmount(newValue.unitVolume, andTimeRemaining: nil))
                    }
                    break
                }
            }

            if newValue.unitVolume > previousVolume + 1 {
                // TODO: report this as a pump event, or?                //self.analyticsServicesManager.reservoirWasRewound()

                pumpDelegate.notify { (delegate) in
                    delegate?.retractAlert(identifier: Self.pumpReservoirLowAlertIdentifier)
                }
            }
        }
    }


    static func reconcilePendingDosesWith(_ events: [NewPumpEvent], reconciliationMappings: [Data:ReconciledDoseMapping], pendingDoses: [UnfinalizedDose]) ->
        (remainingEvents: [NewPumpEvent], reconciliationMappings: [Data:ReconciledDoseMapping], pendingDoses: [UnfinalizedDose]) {
            
        var newReconciliationMapping = reconciliationMappings
        
        var reconcilableEvents = events.filter { !newReconciliationMapping.keys.contains($0.raw) }
        
        // Pending doses can be matched to history events if start time difference is smaller than this
        let matchingTimeWindow = TimeInterval(minutes: 1)
        
        func addReconciliationMapping(startTime: Date, uuid: UUID, eventRaw: Data, index: Int) -> Void {
            let mapping = ReconciledDoseMapping(startTime: startTime, uuid: uuid, eventRaw: eventRaw)
            newReconciliationMapping[eventRaw] = mapping
        }
        
        // Reconcile any pending doses
        let allPending = pendingDoses.map { (dose) -> UnfinalizedDose in
            if let index = reconcilableEvents.firstMatchingIndex(for: dose, within: matchingTimeWindow) {
                let historyEvent = reconcilableEvents[index]
                addReconciliationMapping(startTime: dose.startTime, uuid: dose.uuid, eventRaw: historyEvent.raw, index: index)
                var reconciledDose = dose
                reconciledDose.reconcile(with: historyEvent)
                reconcilableEvents.remove(at: index)
                return reconciledDose
            }
            return dose
        }
            
        // Remove reconciled events
        let remainingPumpEvents = events.filter { (event) -> Bool in
            return newReconciliationMapping[event.raw] == nil
        }
        
        return (remainingEvents: remainingPumpEvents, reconciliationMappings: newReconciliationMapping, pendingDoses: allPending)
    }

    private func reconcilePendingDosesWith(_ events: [NewPumpEvent], fetchedAt: Date) -> [NewPumpEvent] {
        // Must be called from the sessionQueue
        return setStateWithResult { (state) -> [NewPumpEvent] in
            let allPending = (state.pendingDoses + [state.unfinalizedTempBasal, state.unfinalizedBolus]).compactMap({ $0 })
            let result = MinimedPumpManager.reconcilePendingDosesWith(events, reconciliationMappings: state.reconciliationMappings, pendingDoses: allPending)
            state.lastReconciliation = dateGenerator()
            
            // Pending doses and reconciliation mappings will not be kept past this threshold
            let expirationCutoff = dateGenerator().addingTimeInterval(.hours(-12))
            
            state.reconciliationMappings = result.reconciliationMappings.filter { (key, value) -> Bool in
                return value.startTime >= expirationCutoff
            }
            
            state.unfinalizedBolus = nil
            state.unfinalizedTempBasal = nil
            state.pendingDoses = result.pendingDoses.filter { (dose) -> Bool in
                if !dose.isFinished {
                    switch dose.doseType {
                    case .bolus:
                        state.unfinalizedBolus = dose
                        return false
                    case .tempBasal:
                        state.unfinalizedTempBasal = dose
                        return false
                    default:
                        break
                    }
                }

                // If bolus should have ended more than a minute ago, and is not showing in pump history, remove it
                if dose.doseType == .bolus, dose.finishTime < fetchedAt.addingTimeInterval(.minutes(-1)), !dose.isReconciledWithHistory {
                    log.default("Removing bolus that did not reconcile with history: %{public}@", String(describing: dose))
                    return false
                }

                return dose.startTime >= expirationCutoff
            }
            
            if var runningTempBasal = state.unfinalizedTempBasal {
                // Look for following temp basal cancel event in pump history
                if let tempBasalCancellation = result.remainingEvents.first(where: { (event) -> Bool in
                    if let dose = event.dose,
                       dose.type == .tempBasal,
                       dose.startDate > runningTempBasal.startTime,
                       dose.startDate < runningTempBasal.finishTime,
                       dose.startDate.timeIntervalSince(dose.endDate) == 0
                    {
                        return true
                    }
                    return false
                }) {
                    runningTempBasal.cancel(at: tempBasalCancellation.date, pumpModel: state.pumpModel)
                    state.unfinalizedTempBasal = runningTempBasal
                    state.suspendState = .resumed(tempBasalCancellation.date)
                }
            }
            return result.remainingEvents
        }
    }

    /// Polls the pump for new history events and passes them to the loop manager
    ///
    /// - Parameters:
    ///   - completion: A closure called once upon completion
    ///   - error: An error describing why the fetch and/or store failed
    private func fetchPumpHistory(_ completion: @escaping (_ error: Error?) -> Void) {
        guard let insulinType = insulinType else {
            completion(PumpManagerError.configuration(MinimedPumpManagerError.insulinTypeNotConfigured))
            return
        }
        
        rileyLinkDeviceProvider.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                completion(PumpManagerError.connection(MinimedPumpManagerError.noRileyLink))
                return
            }
            
            self.pumpOps.runSession(withName: "Fetch Pump History", using: device) { (session) in
                do {
                    guard let startDate = self.pumpDelegate.call({ (delegate) in
                        return delegate?.startDateToFilterNewPumpEvents(for: self)
                    }) else {
                        preconditionFailure("pumpManagerDelegate cannot be nil")
                    }

                    // Include events up to a minute before startDate, since pump event time and pending event time might be off
                    self.log.default("Fetching history since %{public}@", String(describing: startDate.addingTimeInterval(.minutes(-1))))
                    let (historyEvents, model) = try session.getHistoryEvents(since: startDate.addingTimeInterval(.minutes(-1)))
                    
                    // Reconcile history with pending doses
                    let newPumpEvents = historyEvents.pumpEvents(from: model)
                    
                    // During reconciliation, some pump events may be reconciled as pending doses and removed. Remaining events should be annotated with current insulinType
                    let remainingHistoryEvents = self.reconcilePendingDosesWith(newPumpEvents, fetchedAt: self.dateGenerator()).map { (event) -> NewPumpEvent in
                        return NewPumpEvent(
                            date: event.date,
                            dose: event.dose?.annotated(with: insulinType),
                            raw: event.raw,
                            title: event.title,
                            type: event.type)
                    }

                    self.pumpDelegate.notify({ (delegate) in
                        guard let delegate = delegate else {
                            preconditionFailure("pumpManagerDelegate cannot be nil")
                        }
                        
                        let pendingEvents = (self.state.pendingDoses + [self.state.unfinalizedBolus, self.state.unfinalizedTempBasal]).compactMap({ $0?.newPumpEvent() })

                        self.log.default("Reporting new pump events: %{public}@", String(describing: remainingHistoryEvents + pendingEvents))

                        delegate.pumpManager(self, hasNewPumpEvents: remainingHistoryEvents + pendingEvents, lastReconciliation: self.state.lastReconciliation, replacePendingEvents: true) { (error) in
                            // Called on an unknown queue by the delegate
                            if error == nil {
                                self.recents.lastAddedPumpEvents = self.dateGenerator()
                                self.setState({ (state) in
                                    // Remove any pending doses that have been reconciled and are finished
                                    if let bolus = state.unfinalizedBolus, bolus.isReconciledWithHistory, bolus.isFinished {
                                        state.unfinalizedBolus = nil
                                    }
                                    if let tempBasal = state.unfinalizedTempBasal, tempBasal.isReconciledWithHistory, tempBasal.isFinished {
                                        state.unfinalizedTempBasal = nil
                                    }
                                    state.pendingDoses.removeAll(where: { (dose) -> Bool in
                                        if dose.isReconciledWithHistory && dose.isFinished {
                                            print("Removing stored, finished, reconciled dose: \(dose)")
                                        }
                                        return dose.isReconciledWithHistory && dose.isFinished
                                    })
                                })
                            }
                            completion(error)
                        }
                    })
                } catch let error {
                    self.troubleshootPumpComms(using: device)

                    completion(PumpManagerError.communication(error as? LocalizedError))
                }
            }
        }
    }

    private func storePendingPumpEvents(forceFinalization: Bool = false, _ completion: @escaping (_ error: MinimedPumpManagerError?) -> Void) {
        // Must be called from the sessionQueue
        let events = (self.state.pendingDoses + [self.state.unfinalizedBolus, self.state.unfinalizedTempBasal]).compactMap({ $0?.newPumpEvent(forceFinalization: forceFinalization) })

        log.debug("Storing pending pump events: %{public}@", String(describing: events))

        self.pumpDelegate.notify({ (delegate) in
            guard let delegate = delegate else {
                preconditionFailure("pumpManagerDelegate cannot be nil")
            }

            delegate.pumpManager(self, hasNewPumpEvents: events, lastReconciliation: self.state.lastReconciliation, replacePendingEvents: true) { (error) in
                // Called on an unknown queue by the delegate
                if let error = error {
                    self.log.error("Pump event storage failed: %{public}@", String(describing: error))
                    completion(MinimedPumpManagerError.storageFailure)
                } else {
                    completion(nil)
                }
            }
        })
    }

    // Safe to call from any thread
    private var isPumpDataStale: Bool {
        // How long should we wait before we poll for new pump data?
        let pumpStatusAgeTolerance = rileyLinkDeviceProvider.idleListeningEnabled ? TimeInterval(minutes: 6) : TimeInterval(minutes: 4)

        return isReservoirDataOlderThan(timeIntervalSinceNow: -pumpStatusAgeTolerance)
    }

    // Safe to call from any thread
    private func isReservoirDataOlderThan(timeIntervalSinceNow: TimeInterval) -> Bool {
        let state = self.state
        var lastReservoirDate = state.lastReservoirReading?.validAt ?? .distantPast

        // Look for reservoir data from MySentry that hasn't yet been written (due to 11-second imposed delay)
        if let sentryStatus = recents.latestPumpStatusFromMySentry {
            var components = sentryStatus.pumpDateComponents
            components.timeZone = state.timeZone

            lastReservoirDate = max(components.date ?? .distantPast, lastReservoirDate)
        }

        return lastReservoirDate.timeIntervalSinceNow <= timeIntervalSinceNow
    }

    private func updateBLEHeartbeatPreference() {
        // Must not be called on the delegate's queue
        rileyLinkDeviceProvider.timerTickEnabled = isPumpDataStale || pumpDelegate.call({ (delegate) -> Bool in
            return delegate?.pumpManagerMustProvideBLEHeartbeat(self) == true
        })
    }

    // MARK: - Configuration

    // MARK: Pump

    /// The user's preferred method of fetching insulin data from the pump
    public var preferredInsulinDataSource: InsulinDataSource {
        get {
            return state.preferredInsulinDataSource
        }
        set {
            setState { (state) in
                state.preferredInsulinDataSource = newValue
            }
        }
    }

    /// The pump battery chemistry, for voltage -> percentage calculation
    public var batteryChemistry: BatteryChemistryType {
        get {
            return state.batteryChemistry
        }
        set {
            setState { (state) in
                state.batteryChemistry = newValue
            }
        }
    }

    /// Whether to use MySentry packets on capable pumps:
    public var useMySentry: Bool {
        get {
            return state.useMySentry
        }
        set {
            let oldValue = state.useMySentry
            setState { (state) in
                state.useMySentry = newValue
            }
            if oldValue != newValue {
                let useIdleListening = state.pumpModel.hasMySentry && state.useMySentry
                self.rileyLinkDeviceProvider.idleListeningState = useIdleListening ? MinimedPumpManagerState.idleListeningEnabledDefaults : .disabled
            }
        }
    }

}


// MARK: - PumpManager
extension MinimedPumpManager: PumpManager {
    
    public static let localizedTitle = LocalizedString("Minimed", comment: "Generic title of the minimed pump manager")

    public var localizedTitle: String {
        return String(format: LocalizedString("Minimed %@", comment: "Pump title (1: model number)"), state.pumpModel.rawValue)
    }

    public static var onboardingMaximumBasalScheduleEntryCount: Int {
        return PumpModel.model522.maximumBasalScheduleEntryCount
    }

    public static var onboardingSupportedBasalRates: [Double] {
        return PumpModel.model522.supportedBasalRates
    }

    public static var onboardingSupportedBolusVolumes: [Double] {
        return PumpModel.model522.supportedBolusVolumes
    }

    public static var onboardingSupportedMaximumBolusVolumes: [Double] {
        return onboardingSupportedBolusVolumes
    }

    /*
     It takes a MM pump about 40s to deliver 1 Unit while bolusing
     See: http://www.healthline.com/diabetesmine/ask-dmine-speed-insulin-pumps#3
     */
    private static let deliveryUnitsPerMinute = 1.5

    public var supportedBasalRates: [Double] {
        return state.pumpModel.supportedBasalRates
    }

    public var supportedBolusVolumes: [Double] {
        return state.pumpModel.supportedBolusVolumes
    }

    public var supportedMaximumBolusVolumes: [Double] {
        return state.pumpModel.supportedBolusVolumes
    }

    public var maximumBasalScheduleEntryCount: Int {
        return state.pumpModel.maximumBasalScheduleEntryCount
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        return state.pumpModel.minimumBasalScheduleEntryDuration
    }

    public var pumpRecordsBasalProfileStartEvents: Bool {
        return state.pumpModel.recordsBasalProfileStartEvents
    }

    public var pumpReservoirCapacity: Double {
        return Double(state.pumpModel.reservoirCapacity)
    }

    public var isOnboarded: Bool { state.isOnboarded }

    private func lastSync(for state: MinimedPumpManagerState, recents: MinimedPumpManagerRecents) -> Date? {
        return [state.lastReconciliation, recents.lastContinuousReservoir].compactMap { $0 }.max()
    }

    public var lastSync: Date? {
        return lastSync(for: state, recents: recents)
    }
    
    public var insulinType: InsulinType? {
        get {
            return state.insulinType
        }
        set {
            setState { (state) in
                state.insulinType = newValue
            }
        }
    }
    
    private func status(for state: MinimedPumpManagerState, recents: MinimedPumpManagerRecents) -> PumpManagerStatus {
        let basalDeliveryState: PumpManagerStatus.BasalDeliveryState
        
        switch recents.suspendEngageState {
        case .engaging:
            basalDeliveryState = .suspending
        case .disengaging:
            basalDeliveryState = .resuming
        case .stable:
            switch recents.tempBasalEngageState {
            case .engaging:
                basalDeliveryState = .initiatingTempBasal
            case .disengaging:
                basalDeliveryState = .cancelingTempBasal
            case .stable:
                switch self.state.suspendState {
                case .suspended(let date):
                    basalDeliveryState = .suspended(date)
                case .resumed(let date):
                    if let tempBasal = state.unfinalizedTempBasal {
                        basalDeliveryState = .tempBasal(DoseEntry(tempBasal))
                    } else {
                        basalDeliveryState = .active(date)
                    }
                }
            }
        }
        
        let bolusState: PumpManagerStatus.BolusState
        
        switch recents.bolusEngageState {
        case .engaging:
            bolusState = .initiating
        case .disengaging:
            bolusState = .canceling
        case .stable:
            if let bolus = state.unfinalizedBolus, !bolus.isFinished {
                bolusState = .inProgress(DoseEntry(bolus))
            } else {
                bolusState = .noBolus
            }
        }
        
        return PumpManagerStatus(
            timeZone: state.timeZone,
            device: hkDevice,
            pumpBatteryChargeRemaining: state.batteryPercentage,
            basalDeliveryState: basalDeliveryState,
            bolusState: bolusState,
            insulinType: state.insulinType
        )
    }
    
    public var status: PumpManagerStatus {
        // Acquire the locks just once
        let state = self.state
        let recents = self.recents
        
        return status(for: state, recents: recents)
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
            cgmDelegate.queue = newValue
        }
    }

    // MARK: Methods

    public func completeOnboard() {
        setState({ (state) in
            state.isOnboarded = true
        })
    }

    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        guard let insulinType = insulinType else {
            completion(PumpManagerError.configuration(MinimedPumpManagerError.insulinTypeNotConfigured))
            return
        }
        
        setSuspendResumeState(state: .suspend, insulinType: insulinType, completion: completion)
    }

    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        guard let insulinType = insulinType else {
            completion(PumpManagerError.configuration(MinimedPumpManagerError.insulinTypeNotConfigured))
            return
        }
        
        setSuspendResumeState(state: .resume, insulinType: insulinType, completion: completion)
    }

    public func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }

    public func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }

    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        rileyLinkDeviceProvider.timerTickEnabled = isPumpDataStale || mustProvideBLEHeartbeat
    }

    /**
     Ensures pump data is current by either waking and polling, or ensuring we're listening to sentry packets.
     */
    public func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        rileyLinkDeviceProvider.assertIdleListening(forcingRestart: true)

        guard isPumpDataStale else {
            log.default("Pump data is not stale: lastSync = %{public}@", String(describing: self.lastSync))
            completion?(self.lastSync)
            return
        }

        log.default("Pump data is stale, fetching.")
        refreshPumpData(completion)
    }

    private func refreshPumpData(_ completion: ((Date?) -> Void)?) {
        rileyLinkDeviceProvider.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                let error = PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)
                self.log.error("No devices found while fetching pump data")
                self.pumpDelegate.notify({ (delegate) in
                    delegate?.pumpManager(self, didError: error)
                    completion?(self.lastSync)
                })
                return
            }

            self.pumpOps.runSession(withName: "Get Pump Status", using: device) { (session) in
                do {

                    let status = try session.getCurrentPumpStatus()
                    guard var date = status.clock.date else {
                        assertionFailure("Could not interpret a valid date from \(status.clock) in the system calendar")
                        throw PumpManagerError.configuration(MinimedPumpManagerError.noDate)
                    }

                    // Initialize basal schedule, if unset
                    if self.state.basalSchedule.entries.count == 0, let basalSchedule = try? session.getBasalSchedule() {
                        self.setState { state in
                            state.basalSchedule = basalSchedule
                        }
                    }

                    // Check if the clock should be reset
                    if abs(date.timeIntervalSince(self.dateGenerator())) > .seconds(20) {
                        self.log.error("Pump clock is more than 20 seconds off. Resetting.")
                        self.pumpDelegate.notify({ (delegate) in
                            delegate?.pumpManager(self, didAdjustPumpClockBy: date.timeIntervalSinceNow)
                        })
                        try session.setTimeToNow()

                        guard let newDate = try session.getTime().date else {
                            throw PumpManagerError.configuration(MinimedPumpManagerError.noDate)
                        }

                        date = newDate
                    }
                    self.recents.latestPumpStatus = status

                    self.updateReservoirVolume(status.reservoir, at: date) { result in
                        switch result {
                        case .failure:
                            completion?(self.lastSync)
                        case .success(let areStoredValuesContinuous):
                            if self.state.preferredInsulinDataSource == .pumpHistory || !areStoredValuesContinuous {
                                self.fetchPumpHistory { (error) in
                                    if let error = error {
                                        self.log.error("fetchPumpHistory failed: %{public}@", String(describing: error))
                                    }
                                    completion?(self.lastSync)
                                }
                            }
                        }
                    }
                } catch let error {
                    self.log.error("Failed to fetch pump status: %{public}@", String(describing: error))
                    self.pumpDelegate.notify({ (delegate) in
                        delegate?.pumpManager(self, didError: PumpManagerError.communication(error as? LocalizedError))
                    })
                    self.troubleshootPumpComms(using: device)
                    completion?(self.lastSync)
                }
            }
        }
    }
    
    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        self.state.pumpModel.bolusDeliveryTime(units: units)
    }
    
    public func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (PumpManagerError?) -> Void) {
        let enactUnits = roundToSupportedBolusVolume(units: units)

        guard enactUnits > 0 else {
            assertionFailure("Invalid zero unit bolus")
            return
        }
        
        guard let insulinType = insulinType else {
            completion(.configuration(MinimedPumpManagerError.insulinTypeNotConfigured))
            return
        }


        pumpOps.runSession(withName: "Bolus", usingSelector: rileyLinkDeviceProvider.firstConnectedDevice) { (session) in

            guard let session = session else {
                completion(.connection(MinimedPumpManagerError.noRileyLink))
                return
            }

            if let unfinalizedBolus = self.state.unfinalizedBolus {
                guard unfinalizedBolus.isFinished else {
                    completion(.deviceState(MinimedPumpManagerError.bolusInProgress))
                    return
                }
                
                self.setState({ (state) in
                    state.pendingDoses.append(unfinalizedBolus)
                    state.unfinalizedBolus = nil
                })
            }

            self.recents.bolusEngageState = .engaging

            if case .suspended = self.state.suspendState {
                guard activationType.isAutomatic == false else {
                    self.log.error("Not executing automatic bolus because pump is suspended")
                    self.recents.bolusEngageState = .stable
                    completion(.deviceState(MinimedPumpManagerError.pumpSuspended))
                    return
                }
                do {
                    try self.runSuspendResumeOnSession(suspendResumeState: .resume, session: session, insulinType: insulinType)
                } catch let error {
                    self.recents.bolusEngageState = .stable
                    self.log.error("Failed to resume pump for bolus: %{public}@", String(describing: error))
                    completion(.communication(error as? LocalizedError))
                    return
                }
            }

            let deliveryTime = self.estimatedDuration(toBolus: enactUnits)

            var uncertainBolusError: PumpManagerError? = nil

            if let error = session.setNormalBolus(units: enactUnits) {
                switch error {
                case .certain(let certainError):
                    self.log.error("Bolus failure: %{public}@", String(describing: certainError))
                    if case PumpOpsError.pumpSuspended = certainError {
                        self.setState { state in
                            state.suspendState = .suspended(self.dateGenerator())
                        }
                    }
                    self.recents.bolusEngageState = .stable
                    completion(.communication(certainError))
                    return
                case .uncertain(let uncertainError):
                    uncertainBolusError = .communication(error)
                    self.log.error("Bolus uncertain failure: %{public}@", String(describing: uncertainError))
                }
            }

            // Between bluetooth and the radio and firmware, about 2s on average passes before we start tracking
            let commsOffset = TimeInterval(seconds: -2)
            let doseStart = self.dateGenerator().addingTimeInterval(commsOffset)

            let dose = UnfinalizedDose(bolusAmount: enactUnits, startTime: doseStart, duration: deliveryTime, insulinType: insulinType, automatic: activationType.isAutomatic)
            self.setState({ (state) in
                state.unfinalizedBolus = dose
            })
            self.recents.bolusEngageState = .stable

            self.storePendingPumpEvents({ (error) in
                completion(uncertainBolusError)
            })
        }
    }

    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        
        guard let insulinType = insulinType else {
            completion(.failure(.configuration(MinimedPumpManagerError.insulinTypeNotConfigured)))
            return
        }

        self.recents.bolusEngageState = .disengaging
        setSuspendResumeState(state: .suspend, insulinType: insulinType) { (error) in
            self.recents.bolusEngageState = .stable
            if let error = error {
                completion(.failure(PumpManagerError.communication(error)))
            } else {
                completion(.success(nil))
            }
        }
    }
    
    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (PumpManagerError?) -> Void) {
        guard let insulinType = insulinType else {
            completion(.configuration(MinimedPumpManagerError.insulinTypeNotConfigured))
            return
        }

        pumpOps.runSession(withName: "Set Temp Basal", usingSelector: rileyLinkDeviceProvider.firstConnectedDevice) { (session) in
            guard let session = session else {
                completion(.connection(MinimedPumpManagerError.noRileyLink))
                return
            }
            
            self.recents.tempBasalEngageState = .engaging

            let result = session.setTempBasal(unitsPerHour, duration: duration)
            
            switch result {
            case .success:
                let now = self.dateGenerator()

                let dose = UnfinalizedDose(tempBasalRate: unitsPerHour, startTime: now, duration: duration, insulinType: insulinType, automatic: true)
                
                self.recents.tempBasalEngageState = .stable
                
                let isResumingScheduledBasal = duration < .ulpOfOne

                // If we were successful, then we know we aren't suspended
                self.setState({ (state) in
                    if case .suspended = state.suspendState {
                        state.suspendState = .resumed(now)
                    } else if isResumingScheduledBasal {
                        state.suspendState = .resumed(now)
                    }
                    
                    let pumpModel = state.pumpModel
                    
                    state.unfinalizedTempBasal?.cancel(at: now, pumpModel: pumpModel)
                    if let previousTempBasal = state.unfinalizedTempBasal {
                        state.pendingDoses.append(previousTempBasal)
                    }
                    
                    if isResumingScheduledBasal {
                        state.unfinalizedTempBasal = nil
                    } else {
                        state.unfinalizedTempBasal = dose
                    }
                })

                self.storePendingPumpEvents({ (error) in
                    completion(nil)
                })

                // Continue below
            case .failure(let error):
                completion(.communication(error))

                self.logDeviceCommunication("Set temp basal failed: \(error.localizedDescription)", type: .error)

                // If we got a command-refused error, we might be suspended or bolusing, so update the state accordingly
                if case .arguments(.pumpError(.commandRefused)) = error {
                    do {
                        let status = try session.getCurrentPumpStatus()
                        self.setState({ (state) in
                            if case .resumed = state.suspendState, status.suspended {
                                state.suspendState = .suspended(self.dateGenerator())
                            }
                        })
                        self.recents.latestPumpStatus = status
                    } catch {
                        self.log.error("Post-basal suspend state fetch failed: %{public}@", String(describing: error))
                    }
                }
                self.recents.tempBasalEngageState = .stable
                return
            }
        }
    }

    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        if let bolus = self.state.unfinalizedBolus, !bolus.isFinished {
            return MinimedDoseProgressEstimator(dose: DoseEntry(bolus), pumpModel: state.pumpModel, reportingQueue: dispatchQueue)
        }
        return nil
    }
    
    public func setMaximumTempBasalRate(_ rate: Double) { }

    public func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>], completion: @escaping (Result<BasalRateSchedule, Error>) -> Void) {
        pumpOps.runSession(withName: "Save Basal Profile", usingSelector: rileyLinkDeviceProvider.firstConnectedDevice) { (session) in
            guard let session = session else {
                completion(.failure(PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)))
                return
            }

            do {
                let newSchedule = BasalSchedule(repeatingScheduleValues: scheduleItems)
                try session.setBasalSchedule(newSchedule, for: .standard)


                completion(.success(BasalRateSchedule(dailyItems: scheduleItems, timeZone: session.pump.timeZone)!))
            } catch let error {
                self.log.error("Save basal profile failed: %{public}@", String(describing: error))
                completion(.failure(error))
            }
        }
    }

    public func syncDeliveryLimits(limits deliveryLimits: DeliveryLimits, completion: @escaping (Result<DeliveryLimits, Error>) -> Void) {
        pumpOps.runSession(withName: "Save Settings", usingSelector: rileyLinkDeviceProvider.firstConnectedDevice) { (session) in
            guard let session = session else {
                completion(.failure(PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)))
                return
            }

            do {
                if let maxBasalRate = deliveryLimits.maximumBasalRate?.doubleValue(for: .internationalUnitsPerHour) {
                    try session.setMaxBasalRate(unitsPerHour: maxBasalRate)
                }

                if let maxBolus = deliveryLimits.maximumBolus?.doubleValue(for: .internationalUnit()) {
                    try session.setMaxBolus(units: maxBolus)
                }

                let settings = try session.getSettings()
                let storedDeliveryLimits = DeliveryLimits(maximumBasalRate: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: settings.maxBasal),
                                                          maximumBolus: HKQuantity(unit: .internationalUnit(), doubleValue: settings.maxBolus))
                completion(.success(storedDeliveryLimits))
            } catch let error {
                self.log.error("Save delivery limit settings failed: %{public}@", String(describing: error))
                completion(.failure(error))
            }
        }
    }

    public var isClockOffset: Bool {
        let now = dateGenerator()
        return TimeZone.current.secondsFromGMT(for: now) != state.timeZone.secondsFromGMT(for: now)
    }

    public func setTime(completion: @escaping (PumpManagerError?) -> Void) {
        pumpOps.runSession(withName: "Set time", usingSelector: rileyLinkDeviceProvider.firstConnectedDevice) { (session) in
            do {
                guard let session = session else {
                    throw PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)
                }
                try session.setTimeToNow(in: .current)
                completion(nil)
            } catch let error {
                completion(.communication(error as? LocalizedError))
            }
        }
    }

    public func deletePump(completion: @escaping () -> Void) {
        storePendingPumpEvents(forceFinalization: true) { error in
            self.notifyDelegateOfDeactivation {
                completion()
            }
        }
    }
}

extension MinimedPumpManager: PumpOpsDelegate {
    public func willSend(_ message: String) {
        logDeviceCommunication(message, type: .send)
    }

    public func didReceive(_ message: String) {
        logDeviceCommunication(message, type: .receive)
    }

    public func didError(_ message: String) {
        logDeviceCommunication(message, type: .error)
    }

    public func pumpOps(_ pumpOps: PumpOps, didChange state: PumpState) {
        setState { (pumpManagerState) in
            pumpManagerState.pumpState = state
        }
    }
}

extension MinimedPumpManager: CGMManager {
    public var device: HKDevice? {
        return hkDevice
    }

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            return cgmDelegate.delegate
        }
        set {
            cgmDelegate.delegate = newValue
        }
    }

    public var shouldSyncToRemoteService: Bool {
        return true
    }

    public var providesBLEHeartbeat: Bool {
        return false
    }

    public var managedDataInterval: TimeInterval? {
        return nil
    }

    public var glucoseDisplay: GlucoseDisplayable? {
        return recents.sensorState
    }
    
    public var cgmManagerStatus: CGMManagerStatus {
        return CGMManagerStatus(hasValidSensorSession: hasValidSensorSession, device: device)
    }
    
    public var hasValidSensorSession: Bool {
        // No tracking of session available
        return true
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        rileyLinkDeviceProvider.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                completion(.error(PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)))
                return
            }

            let latestGlucoseDate = self.cgmDelegate.call({ (delegate) -> Date in
                return delegate?.startDateToFilterNewData(for: self) ?? Date(timeIntervalSinceNow: TimeInterval(hours: -24))
            })

            guard latestGlucoseDate.timeIntervalSinceNow <= TimeInterval(minutes: -4.5) else {
                completion(.noData)
                return
            }

            self.pumpOps.runSession(withName: "Fetch Enlite History", using: device) { (session) in
                do {
                    let events = try session.getGlucoseHistoryEvents(since: latestGlucoseDate.addingTimeInterval(.minutes(1)))

                    if let latestSensorEvent = events.compactMap({ $0.glucoseEvent as? RelativeTimestampedGlucoseEvent }).last {
                        self.recents.sensorState = EnliteSensorDisplayable(latestSensorEvent)
                    }

                    let unit = HKUnit.milligramsPerDeciliter
                    let glucoseValues: [NewGlucoseSample] = events
                        // TODO: Is the { $0.date > latestGlucoseDate } filter duplicative?
                        .filter({ $0.glucoseEvent is SensorValueGlucoseEvent && $0.date > latestGlucoseDate })
                        .map {
                            let glucoseEvent = $0.glucoseEvent as! SensorValueGlucoseEvent
                            let quantity = HKQuantity(unit: unit, doubleValue: Double(glucoseEvent.sgv))
                            return NewGlucoseSample(date: $0.date, quantity: quantity, condition: nil, trend: glucoseEvent.trendType, trendRate: glucoseEvent.trendRate, isDisplayOnly: false, wasUserEntered: false, syncIdentifier: glucoseEvent.glucoseSyncIdentifier ?? UUID().uuidString, device: self.device)
                    }

                    completion(.newData(glucoseValues))
                } catch let error {
                    completion(.error(error))
                }
            }
        }
    }
}

// MARK: - AlertResponder implementation
extension MinimedPumpManager {
    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}

// MARK: - AlertSoundVendor implementation
extension MinimedPumpManager {
    public func getSoundBaseURL() -> URL? { return nil }
    public func getSounds() -> [Alert.Sound] { return [] }
}

extension GlucoseTrend {
    var loopKitGlucoseTrend: LoopKit.GlucoseTrend {
        switch self {
        case .flat:
            return .flat
        case .up:
            return .up
        case .upUp:
            return .upUp
        case .down:
            return .down
        case .downDown:
            return .downDown
        }
    }
}
