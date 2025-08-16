import CoreBluetooth
import HealthKit
import LoopKit
import UIKit
import UserNotifications

public protocol StateObserver: AnyObject {
    func stateDidUpdate(_ state: DanaKitPumpManagerState, _ oldState: DanaKitPumpManagerState)
    func deviceScanDidUpdate(_ device: DanaPumpScan)
}

public class DanaKitPumpManager: DeviceManager {
    private(set) var bluetooth: BluetoothManager

    private var oldState: DanaKitPumpManagerState
    public var state: DanaKitPumpManagerState
    public var rawState: PumpManager.RawStateValue {
        state.rawValue
    }

    public static let pluginIdentifier: String = "Dana" // use a single token to make parsing log files easier
    public let managerIdentifier: String = "Dana"

    public var localizedTitle: String {
        state.getFriendlyDeviceName()
    }

    init(state: DanaKitPumpManagerState, dateGenerator _: @escaping () -> Date = Date.init) {
        self.state = state
        oldState = DanaKitPumpManagerState(rawValue: state.rawValue)
        DanaRSEncryption.setEnhancedEncryption(self.state.encryptionMode)

        bluetooth = self.state.isUsingContinuousMode ? ContinousBluetoothManager() : InteractiveBluetoothManager()
        bluetooth.pumpManagerDelegate = self

        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(appMovedToBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(appMovedToForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    public required convenience init?(rawState: PumpManager.RawStateValue) {
        self.init(state: DanaKitPumpManagerState(rawValue: rawState))
    }

    private let log = DanaLogger(category: "DanaKitPumpManager")
    public let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()

    private let statusObservers = WeakSynchronizedSet<PumpManagerStatusObserver>()
    private let stateObservers = WeakSynchronizedSet<StateObserver>()
    private let scanDeviceObservers = WeakSynchronizedSet<StateObserver>()

    private var isPriming = false
    private var bolusCallback: CheckedContinuation<Void, Never>?
    private var doseReporter: DanaKitDoseProgressReporter?
    private var doseEntry: UnfinalizedDose?

    public var isOnboarded: Bool {
        state.isOnBoarded
    }

    public var isBluetoothConnected: Bool {
        bluetooth.isConnected
    }

    private let basalIntervals: [TimeInterval] = Array(0 ..< 24).map({ TimeInterval(60 * 60 * $0) })
    public var currentBaseBasalRate: Double {
        guard !state.basalSchedule.isEmpty else {
            // Prevent crash if basalSchedule isnt set
            return 0
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let nowTimeInterval = now.timeIntervalSince(startOfDay)

        let index = (basalIntervals.firstIndex(where: { $0 > nowTimeInterval }) ?? 24) - 1
        return state.basalSchedule.indices.contains(index) ? state.basalSchedule[index] : 0
    }

    public var status: PumpManagerStatus {
        self.status(state)
    }

    public var debugDescription: String {
        let lines = [
            "## DanaKitPumpManager",
            state.debugDescription
        ]
        return lines.joined(separator: "\n")
    }

    public func connect(_ peripheral: CBPeripheral, _ completion: @escaping (ConnectionResult) -> Void) {
        bluetooth.connect(peripheral, completion)
    }

    public func disconnect(_ force: Bool = false) {
        guard bluetooth.isConnected else {
            // Disconnect is not needed
            return
        }

        bluetooth.disconnect(bluetooth.peripheral!, force: force)
    }

    public func disconnect(_ peripheral: CBPeripheral, _ force: Bool = false) {
        bluetooth.disconnect(peripheral, force: force)
        state.resetState()
    }

    public func startScan() throws {
        try bluetooth.startScan()
    }

    public func stopScan() {
        bluetooth.stopScan()
    }

    func finishV3Pairing(_ pairingKey: Data, _ randomPairingKey: Data) throws {
        try bluetooth.finishV3Pairing(pairingKey, randomPairingKey)
    }

    // Not persisted
    var provideHeartbeat: Bool = false

    private var lastHeartbeat: Date = .distantPast

    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        provideHeartbeat = mustProvideBLEHeartbeat
    }

    private func issueHeartbeatIfNeeded() {
        if provideHeartbeat, Date().timeIntervalSince(lastHeartbeat) > 2 * 60 {
            pumpDelegate.notify { delegate in
                guard let delegate = delegate else {
                    self.log.error("Heartbeat fire could not be reported -> Missing delegate")
                    return
                }

                delegate.pumpManagerBLEHeartbeatDidFire(self)
            }
            lastHeartbeat = Date()
        }
    }

    public func toggleBluetoothMode() {
        state.isUsingContinuousMode = !state.isUsingContinuousMode

        bluetooth = state.isUsingContinuousMode ? ContinousBluetoothManager() : InteractiveBluetoothManager()
        bluetooth.pumpManagerDelegate = self

        notifyStateDidChange()
    }

    public func reconnect(_ callback: @escaping (Bool) -> Void) {
        if let bluetoothManager = bluetooth as? ContinousBluetoothManager {
            bluetoothManager.reconnect { result in
                callback(result)
            }
        } else {
            log
                .error(
                    "Cannot reconnect in interactive mode, please use Coninuous mode for this or just the ensurePumpConnected function"
                )
            callback(false)
        }
    }

    private let backgroundTask = BackgroundTask()
    @objc func appMovedToBackground() {
        if state.useSilentTones {
            log.info("Starting silent tones")
            backgroundTask.startBackgroundTask()
        }
    }

    @objc func appMovedToForeground() {
        backgroundTask.stopBackgroundTask()
    }
}

extension DanaKitPumpManager: PumpManager {
    public static var onboardingMaximumBasalScheduleEntryCount: Int {
        24
    }

    public static var onboardingSupportedBasalRates: [Double] {
        // 0.01 units for rates between 0.00-3U/hr
        // 0 U/hr is a supported scheduled basal rate
        (0 ... 300).map { Double($0) / 100 }
    }

    public static var onboardingSupportedBolusVolumes: [Double] {
        // 0.05 units for rates between 0.05-30U
        // 0 is not a supported bolus volume
        (1 ... 600).map { Double($0) / 20 }
    }

    public static var onboardingSupportedMaximumBolusVolumes: [Double] {
        DanaKitPumpManager.onboardingSupportedBolusVolumes
    }

    public var delegateQueue: DispatchQueue! {
        get {
            pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }

    public var supportedBasalRates: [Double] {
        DanaKitPumpManager.onboardingSupportedBasalRates
    }

    public var supportedBolusVolumes: [Double] {
        DanaKitPumpManager.onboardingSupportedBolusVolumes
    }

    public var supportedMaximumBolusVolumes: [Double] {
        // 0.05 units for rates between 0.05-30U
        // 0 is not a supported bolus volume
        DanaKitPumpManager.onboardingSupportedBolusVolumes
    }

    public var maximumBasalScheduleEntryCount: Int {
        DanaKitPumpManager.onboardingMaximumBasalScheduleEntryCount
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        // One per hour
        TimeInterval(60 * 60)
    }

    public func roundToSupportedBolusVolume(units: Double) -> Double {
        // We do support rounding a 0 U volume to 0
        supportedBolusVolumes.last(where: { $0 <= units }) ?? 0
    }

    public func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
        supportedBasalRates.last(where: { $0 <= unitsPerHour }) ?? 0
    }

    public var pumpManagerDelegate: LoopKit.PumpManagerDelegate? {
        get {
            pumpDelegate.delegate
        }
        set {
            pumpDelegate.delegate = newValue
        }
    }

    public var pumpRecordsBasalProfileStartEvents: Bool {
        false
    }

    public var pumpReservoirCapacity: Double {
        Double(state.reservoirLevel)
    }

    public var lastSync: Date? {
        state.lastStatusDate
    }

    private func status(_ state: DanaKitPumpManagerState) -> LoopKit.PumpManagerStatus {
        // Check if temp basal is expired, before constructing basalDeliveryState
        if self.state.basalDeliveryOrdinal == .tempBasal, self.state.tempBasalEndsAt < Date.now {
            self.state.basalDeliveryOrdinal = .active
            self.state.basalDeliveryDate = Date.now
            self.state.tempBasalDuration = nil
            self.state.tempBasalUnits = nil
        }

        return PumpManagerStatus(
            timeZone: state.pumpTimeZone ?? TimeZone.current,
            device: device(),
            pumpBatteryChargeRemaining: state.batteryRemaining / 100,
            basalDeliveryState: state.basalDeliveryState,
            bolusState: bolusState(state.bolusState),
            insulinType: state.insulinType
        )
    }

    private func bolusState(_ bolusState: BolusState) -> PumpManagerStatus.BolusState {
        switch bolusState {
        case .noBolus:
            return .noBolus
        case .initiating:
            return .initiating
        case .canceling:
            return .canceling
        case .inProgress:
            if let dose = doseEntry?.toDoseEntry() {
                return .inProgress(dose)
            }

            return .noBolus
        }
    }

    public func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        guard Date.now.timeIntervalSince(state.lastStatusDate) > .minutes(4) else {
            log
                .warning(
                    "Skipping status update because pumpData is fresh: \(Date.now.timeIntervalSince(state.lastStatusDate)) sec"
                )
            completion?(state.lastStatusDate)
            return
        }

        if bluetooth as? ContinousBluetoothManager != nil, status.bolusState != .noBolus {
            log.warning("Skipping status update because bolus is running...")
            completion?(state.lastStatusDate)
            return
        }

        syncPump(completion)
    }

    /// Extention from ensureCurrentPumpData, but overrides the stale data check
    public func syncPump(_ completion: ((Date?) -> Void)?) {
        log.info("Syncing pump data")

        bluetooth.ensureConnected { result in
            switch result {
            case .success:
                await self.syncUserOptions()
                let events = await self.syncHistory()

                if self.shouldSyncTime() {
                    await self.syncTime()
                }

                let pumpTime = await self.fetchPumpTime()
                if let pumpTime = pumpTime {
                    self.state.pumpTimeSyncedAt = Date.now
                    self.state.pumpTime = pumpTime
                }

                self.state.lastStatusPumpDateTime = pumpTime ?? Date.now
                self.state.lastStatusDate = Date.now
                self.disconnect()

                self.issueHeartbeatIfNeeded()
                self.notifyStateDidChange()

                self.pumpDelegate.notify { delegate in
                    guard let delegate = delegate else {
                        self.log.error("Reservoir level & last check could not be reported -> Missing delegate")
                        return
                    }

                    delegate.pumpManager(
                        self,
                        hasNewPumpEvents: events,
                        lastReconciliation: self.state.lastStatusDate,
                        replacePendingEvents: true,
                        completion: { _ in }
                    )
                    delegate.pumpManager(
                        self,
                        didReadReservoirValue: self.state.reservoirLevel,
                        at: Date.now,
                        completion: { _ in }
                    )
                    delegate.pumpManagerDidUpdateState(self)
                }

                self.log.info("Sync successful!")
                completion?(Date.now)
            default:
                completion?(nil)
                return
            }
        }
    }

    private func syncTime() async {
        await withCheckedContinuation { continuation in
            self.syncPumpTime { error in
                if let error = error {
                    self.log.error("Failed to automaticly sync pump time: \(error.localizedDescription)")
                }

                continuation.resume()
            }
        }
    }

    private func shouldSyncTime() -> Bool {
        guard state.allowAutomaticTimeSync else {
            return false
        }
        guard let pumpTime = state.pumpTime else {
            return false
        }

        let pumpTimeComp = Calendar.current.dateComponents([.day], from: pumpTime)
        let nowComp = Calendar.current.dateComponents([.day], from: Date.now)
        return pumpTimeComp.day != nowComp.day
    }

    private func syncUserOptions() async {
        do {
            let userOptionPacket = generatePacketGeneralGetUserOption()
            let userOptionResult = try await bluetooth.writeMessage(userOptionPacket)
            guard userOptionResult.success else {
                log.error("Failed to fetch user options...")
                return
            }

            let dataUserOption = userOptionResult.data as! PacketGeneralGetUserOption
            state.lowReservoirRate = dataUserOption.lowReservoirRate
            state.isTimeDisplay24H = dataUserOption.isTimeDisplay24H
            state.isButtonScrollOnOff = dataUserOption.isButtonScrollOnOff
            state.beepAndAlarm = dataUserOption.beepAndAlarm
            state.lcdOnTimeInSec = dataUserOption.lcdOnTimeInSec
            state.backlightOnTimInSec = dataUserOption.backlightOnTimInSec
            state.selectedLanguage = dataUserOption.selectedLanguage
            state.units = dataUserOption.units
            state.shutdownHour = dataUserOption.shutdownHour
            state.cannulaVolume = dataUserOption.cannulaVolume
            state.refillAmount = dataUserOption.refillAmount
            state.targetBg = dataUserOption.targetBg
            state.units = dataUserOption.units
        } catch {
            log.error("Failed to sync user options: \(error.localizedDescription)")
        }
    }

    private func fetchPumpTime() async -> Date? {
        do {
            let timePacket = state
                .usingUtc ? generatePacketGeneralGetPumpTimeUtcWithTimezone() : generatePacketGeneralGetPumpTime()
            let timeResult = try await bluetooth.writeMessage(timePacket)

            guard timeResult.success else {
                log.error("Failed to fetch pump time with utc...")
                return nil
            }

            if let data = timeResult.data as? PacketGeneralGetPumpTimeUtcWithTimezone {
                state.pumpTimeZone = TimeZone(secondsFromGMT: data.timezoneOffset * 3600)
            }

            let date = state.usingUtc ? (timeResult.data as? PacketGeneralGetPumpTimeUtcWithTimezone)?
                .time : (timeResult.data as? PacketGeneralGetPumpTime)?.time
            guard let date = date else {
                return nil
            }

            return date
        } catch {
            log.error("Failed to sync time: \(error.localizedDescription)")
            return nil
        }
    }

    private func syncHistory() async -> [NewPumpEvent] {
        var hasHistoryModeBeenActivate = false
        do {
            let activateHistoryModePacket =
                generatePacketGeneralSetHistoryUploadMode(options: PacketGeneralSetHistoryUploadMode(mode: 1))
            let activateHistoryModeResult = try await bluetooth.writeMessage(activateHistoryModePacket)
            guard activateHistoryModeResult.success else {
                return []
            }

            hasHistoryModeBeenActivate = true

            let fetchHistoryPacket =
                generatePacketHistoryAll(options: PacketHistoryBase(from: state.lastStatusPumpDateTime, usingUtc: state.usingUtc))
            let fetchHistoryResult = try await bluetooth.writeMessage(fetchHistoryPacket)
            guard fetchHistoryResult.success else {
                return []
            }

            let deactivateHistoryModePacket =
                generatePacketGeneralSetHistoryUploadMode(options: PacketGeneralSetHistoryUploadMode(mode: 0))
            _ = try await bluetooth.writeMessage(deactivateHistoryModePacket)

            return (fetchHistoryResult.data as! [HistoryItem]).compactMap({ item in
                switch item.code {
                case HistoryCode.RECORD_TYPE_ALARM:
                    return [NewPumpEvent(
                        date: item.timestamp,
                        dose: nil,
                        raw: item.raw,
                        title: "Alarm: \(getAlarmMessage(param8: item.alarm))",
                        type: .alarm,
                        alarmType: PumpAlarmType.fromParam8(item.alarm)
                    )]

                case HistoryCode.RECORD_TYPE_BOLUS:
                    // Skip bolus syncing if enabled by user
                    if self.state.isBolusSyncDisabled {
                        return []
                    }

                    // If we find a bolus here, we assume that is hasnt been synced to Loop
                    return [NewPumpEvent.bolus(
                        dose: DoseEntry.bolus(
                            units: item.value!,
                            deliveredUnits: item.value!,
                            duration: item.durationInMin! * 60,
                            activationType: .manualNoRecommendation,
                            insulinType: self.state.insulinType!,
                            startDate: item.timestamp
                        ),
                        units: item.value!,
                        date: item.timestamp
                    )]

                case HistoryCode.RECORD_TYPE_SUSPEND:
                    if item.value! == 1 {
                        return [NewPumpEvent.suspend(dose: DoseEntry.suspend(suspendDate: item.timestamp))]
                    } else {
                        return [NewPumpEvent.resume(
                            dose: DoseEntry.resume(insulinType: self.state.insulinType!, resumeDate: item.timestamp),
                            date: item.timestamp
                        )]
                    }

                case HistoryCode.RECORD_TYPE_PRIME:
                    guard let value = item.value, value < 1 else {
                        // This is a tube refill, not a canulla refill
                        return []
                    }

                    if self.state.cannulaDate == nil {
                        self.state.cannulaDate = item.timestamp
                    } else if let cannulaDate = self.state.cannulaDate, item.timestamp > cannulaDate {
                        self.state.cannulaDate = item.timestamp
                    }

                    return [
                        NewPumpEvent(
                            date: item.timestamp,
                            dose: nil,
                            raw: item.raw,
                            title: "Prime \(value)U",
                            type: .prime,
                            alarmType: nil
                        ),
                        NewPumpEvent(
                            date: item.timestamp,
                            dose: nil,
                            raw: item.raw,
                            title: "Prime \(value)U",
                            type: .replaceComponent(componentType: .infusionSet),
                            alarmType: nil
                        )
                    ]

                case HistoryCode.RECORD_TYPE_REFILL:
                    if self.state.reservoirDate == nil {
                        self.state.reservoirDate = item.timestamp
                    } else if let reservoirDate = self.state.reservoirDate, item.timestamp > reservoirDate {
                        self.state.reservoirDate = item.timestamp
                    }

                    return [
                        NewPumpEvent(
                            date: item.timestamp,
                            dose: nil,
                            raw: item.raw,
                            title: "Rewind \(item.value ?? 0)U",
                            type: .rewind,
                            alarmType: nil
                        ),
                        NewPumpEvent(
                            date: item.timestamp,
                            dose: nil,
                            raw: item.raw,
                            title: "Rewind \(item.value ?? 0)U",
                            type: .replaceComponent(componentType: .reservoir),
                            alarmType: nil
                        )
                    ]

                default:
                    return []
                }
            })
                // Transform array from 2d to 1d array
                .flatMap { $0 }

        } catch {
            log.error("Failed to sync history. Error: \(error.localizedDescription)")
            if hasHistoryModeBeenActivate {
                do {
                    let deactivateHistoryModePacket =
                        generatePacketGeneralSetHistoryUploadMode(options: PacketGeneralSetHistoryUploadMode(mode: 0))
                    _ = try await bluetooth.writeMessage(deactivateHistoryModePacket)
                } catch {}
            }
            return []
        }
    }

    public func createBolusProgressReporter(reportingOn _: DispatchQueue) -> DoseProgressReporter? {
        doseReporter
    }

    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        switch state.bolusSpeed {
        case .speed12:
            return units * 12 // 12sec/U
        case .speed30:
            return units * 30 // 30sec/U
        case .speed60:
            return units * 60 // 60sec/U
        }
    }

    public func enactBolus(
        units: Double,
        activationType: BolusActivationType,
        completion: @escaping (PumpManagerError?) -> Void
    ) {
        guard state.bolusState == .noBolus else {
            log.error("Pump already busy bolussing")
            completion(.deviceState(DanaKitPumpManagerError.pumpIsBusy))
            return
        }

        guard let insulinType = state.insulinType else {
            log.error("Insulin type is nil...")
            completion(.configuration(DanaKitPumpManagerError.unknown("Missing insulin type")))
            return
        }

        delegateQueue.async {
            let duration = self.estimatedDuration(toBolus: units)
            self.log.info("Enact bolus, units: \(units)U, duration: \(duration)sec")

            self.state.bolusState = .initiating
            self.notifyStateDidChange()

            self.bluetooth.ensureConnected { result in
                switch result {
                case .success:
                    guard !self.state.isPumpSuspended else {
                        self.state.bolusState = .noBolus
                        self.doseReporter = nil
                        self.doseEntry = nil
                        self.notifyStateDidChange()
                        self.disconnect()

                        self.log.error("Pump is suspended")
                        completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpSuspended))
                        return
                    }

                    do {
                        let packet =
                            generatePacketBolusStart(options: PacketBolusStart(
                                amount: units,
                                speed: !self.isPriming ? self.state.bolusSpeed : .speed12
                            ))
                        let result = try await self.bluetooth.writeMessage(packet)

                        guard result.success else {
                            self.state.bolusState = .noBolus
                            self.doseReporter = nil
                            self.doseEntry = nil
                            self.notifyStateDidChange()
                            self.disconnect()

                            self.log.error("Pump rejected command. Data: \(result.rawData.base64EncodedString())")
                            completion(PumpManagerError.deviceState(transformBolusError(code: result.rawData[DataStart])))
                            return
                        }

                        // Sync the pump time
                        self.state.lastStatusPumpDateTime = await self.fetchPumpTime() ?? Date.now
                        self.state.lastStatusDate = Date.now

                        let doseEntry = UnfinalizedDose(
                            units: units,
                            duration: duration,
                            activationType: activationType,
                            insulinType: insulinType
                        )

                        self.doseEntry = doseEntry
                        self.doseReporter = DanaKitDoseProgressReporter(total: units)
                        self.state.bolusState = .inProgress

                        if !self.isPriming {
                            let dose = doseEntry.toDoseEntry(isMutable: true)
                            await withCheckedContinuation { continuation in
                                self.pumpDelegate.notify { delegate in
                                    guard let delegate = delegate else {
                                        self.log.error("Dose could not be reported -> Missing delegate")
                                        continuation.resume()
                                        return
                                    }

                                    delegate.pumpManager(
                                        self,
                                        hasNewPumpEvents: [
                                            NewPumpEvent
                                                .bolus(
                                                    dose: dose,
                                                    units: dose.programmedUnits,
                                                    date: dose.startDate
                                                )
                                        ],
                                        lastReconciliation: Date.now,
                                        replacePendingEvents: false,
                                        completion: { _ in
                                            continuation.resume()
                                        }
                                    )
                                }
                            }
                        }

                        self.notifyStateDidChange()

                        await withCheckedContinuation { continuation in
                            self.bolusCallback = continuation

                            completion(nil)
                        }
                    } catch {
                        self.state.bolusState = .noBolus
                        self.doseReporter = nil
                        self.notifyStateDidChange()
                        self.disconnect()

                        self.log.error("Failed to do bolus. Error: \(error.localizedDescription)")
                        completion(PumpManagerError.connection(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                default:
                    self.log.error("Connection error")
                    self.state.bolusState = .noBolus
                    self.doseReporter = nil
                    self.notifyStateDidChange()

                    completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection(result)))
                    return
                }
            }
        }
    }

    public func enactPrime(unit: Double, completion: @escaping (PumpManagerError?) -> Void) {
        isPriming = true
        enactBolus(units: unit, activationType: .manualNoRecommendation) { error in
            if let error = error {
                self.isPriming = false
                completion(error)
                return
            }

            completion(nil)
        }
    }

    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        delegateQueue.async {
            self.log.info("Cancel bolus")

            let oldBolusState = self.state.bolusState
            self.state.bolusState = .canceling
            self.notifyStateDidChange()

            // It is very likely that Loop is doing a bolus if the cancel action is triggerd
            // Therefore, we can reuse the connection and directly send the cancel command
            if self.bluetooth.isConnected && self.bluetooth.peripheral?.state == .connected {
                Task {
                    await self.doCancelAction(oldBolusState: oldBolusState, completion: completion)
                }
                return
            }

            self.bluetooth.ensureConnected { result in
                switch result {
                case .success:
                    await self.doCancelAction(oldBolusState: oldBolusState, completion: completion)
                default:
                    self.state.bolusState = oldBolusState
                    self.notifyStateDidChange()

                    completion(.failure(PumpManagerError.connection(DanaKitPumpManagerError.noConnection(result))))
                    return
                }
            }
        }
    }

    private func doCancelAction(oldBolusState: BolusState, completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) async {
        do {
            let packet = generatePacketBolusStop()
            let result = try await bluetooth.writeMessage(packet)

            if !result.success {
                state.bolusState = oldBolusState
                notifyStateDidChange()

                completion(.failure(PumpManagerError.communication(nil)))
                return
            }

            // Sync the pump time
            state.lastStatusPumpDateTime = await fetchPumpTime() ?? Date.now
            state.lastStatusDate = Date.now

            disconnect()
            state.bolusState = .noBolus
            notifyStateDidChange()

            if let bolusCallback = self.bolusCallback {
                bolusCallback.resume()
                self.bolusCallback = nil
            }

            guard let doseEntry = self.doseEntry else {
                completion(.success(nil))
                return
            }

            let dose = doseEntry.toDoseEntry()
            self.doseEntry = nil
            doseReporter = nil

            sendCancelEvent(dose)
            completion(.success(nil))
        } catch {
            state.bolusState = oldBolusState
            notifyStateDidChange()
            disconnect()

            log.error("Failed to cancel bolus. Error: \(error.localizedDescription)")
            completion(.failure(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription))))
        }
    }

    private func sendCancelEvent(_ dose: DoseEntry) {
        DispatchQueue.main.async {
            self.pumpDelegate.notify { delegate in
                guard let delegate = delegate else {
                    self.log.error("Dose could not be reported -> Missing delegate")
                    return
                }

                delegate.pumpManager(
                    self,
                    hasNewPumpEvents: [NewPumpEvent.bolus(dose: dose, units: dose.deliveredUnits ?? 0, date: dose.startDate)],
                    lastReconciliation: Date.now,
                    replacePendingEvents: true,
                    completion: { _ in }
                )
            }

            self.notifyStateDidChange()
        }
    }

    /// NOTE: There are 2 ways to set a temp basal:
    /// - The normal way (which only accepts full hours and percentages)
    /// - A short APS-special temp basal command (which only accepts 15 min or 30 min
    /// Currently, this is implemented with a simpel U/hr -> % calculator
    /// NOTE: A temp basal >200% for 30 min (or full hour) is rescheduled to 15min
    public func enactTempBasal(
        unitsPerHour: Double,
        for duration: TimeInterval,
        completion: @escaping (PumpManagerError?) -> Void
    ) {
        delegateQueue.async {
            self.log.info("Enact temp basal. Value: \(unitsPerHour) U/hr, duration: \(duration) sec")

            self.bluetooth.ensureConnected { result in
                switch result {
                case .success:
                    guard !self.state.isPumpSuspended else {
                        self.log.error("Pump is suspended")
                        self.disconnect()
                        completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpSuspended))
                        return
                    }

                    do {
                        // Check if duration is supported
                        // If not, round it down to nearest supported duration
                        var duration = duration
                        if !self.isSupportedDuration(duration) {
                            let oldDuration = duration
                            if duration > .hours(1) {
                                // Round down to nearest full hour
                                duration = .hours(1) * floor(duration / .hours(1))
                                self.log
                                    .info(
                                        "Temp basal rounded down from \(oldDuration / .hours(1))h to \(floor(duration / .hours(1)))h"
                                    )

                            } else if duration > .minutes(30) {
                                // Round down to 30 min
                                duration = .minutes(30)
                                self.log.info("Temp basal rounded down from \(oldDuration / .minutes(1))min to 30min")

                            } else if duration > .minutes(15) {
                                // Round down to 15 min
                                duration = .minutes(15)
                                self.log.info("Temp basal rounded down from \(oldDuration / .minutes(1))min to 15min")

                            } else {
                                self.disconnect()
                                self.log.error("Temp basal below 15 min is unsupported (floor duration)")
                                completion(
                                    PumpManagerError
                                        .configuration(
                                            DanaKitPumpManagerError
                                                .failedTempBasalAdjustment(
                                                    "Temp basal below 15 min is unsupported... (floor duration)"
                                                )
                                        )
                                )
                                return
                            }
                        }

                        guard let percentage = self.absoluteBasalRateToPercentage(
                            absoluteValue: unitsPerHour,
                            basalSchedule: self.state.basalSchedule
                        ) else {
                            self.disconnect()
                            self.log.error("Basal schedule is not available...")
                            completion(
                                PumpManagerError
                                    .configuration(
                                        DanaKitPumpManagerError
                                            .failedTempBasalAdjustment("Basal schedule is not available...")
                                    )
                            )
                            return
                        }

                        // Temp basal >15min && >200% is not supported
                        // Floor it down to 15min
                        if percentage > 200, duration != .minutes(15) {
                            duration = .minutes(15)
                        }

                        if self.state.isTempBasalInProgress {
                            let packet = generatePacketBasalCancelTemporary()
                            let result = try await self.bluetooth.writeMessage(packet)

                            guard result.success else {
                                self.disconnect()
                                self.log.error("Could not cancel old temp basal")
                                completion(
                                    PumpManagerError
                                        .configuration(
                                            DanaKitPumpManagerError
                                                .failedTempBasalAdjustment("Could not cancel old temp basal")
                                        )
                                )
                                return
                            }

                            self.log.info("Successfully canceled old temp basal")
                        }

                        if duration < .ulpOfOne {
                            // Temp basal is already canceled (if deem needed)
                            self.disconnect()

                            self.state.basalDeliveryOrdinal = .active
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = nil
                            self.state.tempBasalDuration = nil
                            self.notifyStateDidChange()

                            let dose = DoseEntry.basal(rate: self.currentBaseBasalRate, insulinType: self.state.insulinType!)
                            self.pumpDelegate.notify { delegate in
                                guard let delegate = delegate else {
                                    self.log.error("Basal reset could not be reported -> Missing delegate")
                                    return
                                }

                                delegate.pumpManager(
                                    self,
                                    hasNewPumpEvents: [NewPumpEvent.basal(dose: dose)],
                                    lastReconciliation: Date.now,
                                    replacePendingEvents: true,
                                    completion: { _ in }
                                )
                            }

                            self.log.info("Successfully cancelled temp basal")
                            completion(nil)

                        } else if duration == .minutes(15) {
                            let packet =
                                generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal(
                                    percent: percentage,
                                    duration: .min15
                                ))
                            let result = try await self.bluetooth.writeMessage(packet)
                            self.disconnect()

                            guard result.success else {
                                self.log.error("Pump rejected command (15 min)")
                                completion(
                                    PumpManagerError
                                        .configuration(
                                            DanaKitPumpManagerError
                                                .failedTempBasalAdjustment("Pump rejected command (15 min)")
                                        )
                                )
                                return
                            }

                            let dose = DoseEntry.tempBasal(
                                absoluteUnit: unitsPerHour,
                                duration: duration,
                                insulinType: self.state.insulinType!
                            )
                            self.state.basalDeliveryOrdinal = .tempBasal
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = unitsPerHour
                            self.state.tempBasalDuration = duration
                            self.notifyStateDidChange()

                            self.pumpDelegate.notify { delegate in
                                guard let delegate = delegate else {
                                    self.log.error("Temp basal could not be reported -> Missing delegate")
                                    return
                                }

                                delegate.pumpManager(
                                    self,
                                    hasNewPumpEvents: [
                                        NewPumpEvent
                                            .tempBasal(dose: dose, units: unitsPerHour, duration: duration)
                                    ],
                                    lastReconciliation: Date.now,
                                    replacePendingEvents: true,
                                    completion: { _ in }
                                )
                            }

                            self.log.info("Successfully started 15 min temp basal")
                            completion(nil)

                        } else if duration == .minutes(30) {
                            let packet =
                                generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal(
                                    percent: percentage,
                                    duration: .min30
                                ))
                            let result = try await self.bluetooth.writeMessage(packet)
                            self.disconnect()

                            guard result.success else {
                                self.log.error("Pump rejected command (30 min)")
                                completion(
                                    PumpManagerError
                                        .configuration(
                                            DanaKitPumpManagerError
                                                .failedTempBasalAdjustment("Pump rejected command (30 min)")
                                        )
                                )
                                return
                            }

                            let dose = DoseEntry.tempBasal(
                                absoluteUnit: unitsPerHour,
                                duration: duration,
                                insulinType: self.state.insulinType!
                            )
                            self.state.basalDeliveryOrdinal = .tempBasal
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = unitsPerHour
                            self.state.tempBasalDuration = duration
                            self.notifyStateDidChange()

                            self.pumpDelegate.notify { delegate in
                                guard let delegate = delegate else {
                                    self.log.error("Temp basal could not be reported -> Missing delegate")
                                    return
                                }

                                delegate.pumpManager(
                                    self,
                                    hasNewPumpEvents: [
                                        NewPumpEvent
                                            .tempBasal(dose: dose, units: unitsPerHour, duration: duration)
                                    ],
                                    lastReconciliation: Date.now,
                                    replacePendingEvents: true,
                                    completion: { _ in }
                                )
                            }

                            self.log.info("Successfully started 30 min temp basal")
                            completion(nil)

                            // Full hour
                        } else {
                            let durationInHours = UInt8(floor(duration / .hours(1)))
                            let packet =
                                generatePacketBasalSetTemporary(
                                    options: PacketBasalSetTemporary(
                                        temporaryBasalRatio: UInt8(percentage),
                                        temporaryBasalDuration: durationInHours
                                    )
                                )
                            let result = try await self.bluetooth.writeMessage(packet)
                            self.disconnect()

                            guard result.success else {
                                self.log.error("Pump rejected command (full hour)")
                                completion(
                                    PumpManagerError
                                        .configuration(
                                            DanaKitPumpManagerError
                                                .failedTempBasalAdjustment("Pump rejected command (full hour)")
                                        )
                                )
                                return
                            }

                            let dose = DoseEntry.tempBasal(
                                absoluteUnit: unitsPerHour,
                                duration: duration,
                                insulinType: self.state.insulinType!
                            )
                            self.state.basalDeliveryOrdinal = .tempBasal
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = unitsPerHour
                            self.state.tempBasalDuration = duration
                            self.notifyStateDidChange()

                            self.pumpDelegate.notify { delegate in
                                guard let delegate = delegate else {
                                    self.log.error("Temp basal could not be reported -> Missing delegate")
                                    return
                                }

                                delegate.pumpManager(
                                    self,
                                    hasNewPumpEvents: [
                                        NewPumpEvent
                                            .tempBasal(dose: dose, units: unitsPerHour, duration: duration)
                                    ],
                                    lastReconciliation: Date.now,
                                    replacePendingEvents: true,
                                    completion: { _ in }
                                )
                            }

                            self.log.info("Successfully started \(durationInHours)h temp basal")
                            completion(nil)
                        }
                    } catch {
                        self.disconnect()

                        self.log.error("Failed to set temp basal. Error: \(error.localizedDescription)")
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                default:
                    self.log.error("Connection error")
                    completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection(result)))
                    return
                }
            }
        }
    }

    private func isSupportedDuration(_ duration: TimeInterval) -> Bool {
        duration < .ulpOfOne || duration == .minutes(15) || duration == .minutes(30) || Int(duration) % Int(.hours(1)) == 0
    }

    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        delegateQueue.async {
            self.log.info("Suspend delivery")

            self.bluetooth.ensureConnected { result in
                switch result {
                case .success:
                    do {
                        let packet = generatePacketBasalSetSuspendOn()
                        let result = try await self.bluetooth.writeMessage(packet)

                        let pumpTime = await self.fetchPumpTime()
                        if let pumpTime = pumpTime {
                            self.state.pumpTimeSyncedAt = Date.now
                            self.state.pumpTime = pumpTime
                        }

                        self.disconnect()

                        guard result.success else {
                            self.log.error("Pump rejected command")
                            completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedSuspensionAdjustment))
                            return
                        }

                        self.state.lastStatusPumpDateTime = pumpTime ?? Date.now
                        self.state.lastStatusDate = Date.now
                        self.state.isPumpSuspended = true
                        self.state.basalDeliveryOrdinal = .suspended
                        self.state.basalDeliveryDate = Date.now
                        self.notifyStateDidChange()

                        let dose = DoseEntry.suspend()
                        self.pumpDelegate.notify { delegate in
                            guard let delegate = delegate else {
                                self.log.error("Suspend could not be reported -> Missing delegate")
                                return
                            }

                            delegate.pumpManager(
                                self,
                                hasNewPumpEvents: [NewPumpEvent.suspend(dose: dose)],
                                lastReconciliation: self.state.lastStatusDate,
                                replacePendingEvents: true,
                                completion: { _ in }
                            )
                        }

                        completion(nil)
                    } catch {
                        self.disconnect()

                        self.log.error("Failed to suspend delivery. Error: \(error.localizedDescription)")
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                default:
                    self.log.error("Connection error")
                    completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection(result)))
                    return
                }
            }
        }
    }

    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        delegateQueue.async {
            self.log.info("Resume delivery")

            self.bluetooth.ensureConnected { result in
                switch result {
                case .success:
                    do {
                        let packet = generatePacketBasalSetSuspendOff()
                        let result = try await self.bluetooth.writeMessage(packet)

                        let pumpTime = await self.fetchPumpTime()
                        if let pumpTime = pumpTime {
                            self.state.pumpTimeSyncedAt = Date.now
                            self.state.pumpTime = pumpTime
                        }

                        self.disconnect()

                        guard result.success else {
                            self.log.error("Pump rejected command")
                            completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedSuspensionAdjustment))
                            return
                        }

                        self.state.lastStatusPumpDateTime = pumpTime ?? Date.now
                        self.state.lastStatusDate = Date.now
                        self.state.isPumpSuspended = false
                        self.state.basalDeliveryOrdinal = .active
                        self.state.basalDeliveryDate = Date.now
                        self.notifyStateDidChange()

                        let dose = DoseEntry.resume(insulinType: self.state.insulinType!)
                        self.pumpDelegate.notify { delegate in
                            guard let delegate = delegate else {
                                self.log.error("Resume could not be reported -> Missing delegate")
                                return
                            }

                            delegate.pumpManager(
                                self,
                                hasNewPumpEvents: [NewPumpEvent.resume(dose: dose)],
                                lastReconciliation: self.state.lastStatusDate,
                                replacePendingEvents: true,
                                completion: { _ in }
                            )
                        }

                        completion(nil)
                    } catch {
                        self.disconnect()

                        self.log.error("Failed to suspend delivery. Error: \(error.localizedDescription)")
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                default:
                    self.log.error("Connection error")
                    completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection(result)))
                    return
                }
            }
        }
    }

    public func syncBasalRateSchedule(
        items scheduleItems: [RepeatingScheduleValue<Double>],
        completion: @escaping (Result<BasalRateSchedule, Error>) -> Void
    ) {
        delegateQueue.async {
            self.log.info("Sync basal")

            self.bluetooth.ensureConnected { result in
                switch result {
                case .success:
                    do {
                        let basal = DanaKitPumpManagerState.convertBasal(scheduleItems)
                        let packet =
                            try generatePacketBasalSetProfileRate(options: PacketBasalSetProfileRate(
                                profileNumber: self.state
                                    .basalProfileNumber,
                                profileBasalRate: basal
                            ))
                        let result = try await self.bluetooth.writeMessage(packet)

                        guard result.success else {
                            self.disconnect()
                            self.log.error("Pump rejected command (setting rates)")
                            completion(.failure(PumpManagerError.configuration(DanaKitPumpManagerError.failedBasalAdjustment)))
                            return
                        }

                        let activatePacket =
                            generatePacketBasalSetProfileNumber(options: PacketBasalSetProfileNumber(
                                profileNumber: self.state
                                    .basalProfileNumber
                            ))
                        let activateResult = try await self.bluetooth.writeMessage(activatePacket)

                        self.disconnect()

                        guard activateResult.success else {
                            self.log.error("Pump rejected command (activate profile)")
                            completion(.failure(PumpManagerError.configuration(DanaKitPumpManagerError.failedBasalAdjustment)))
                            return
                        }

                        guard let schedule = DailyValueSchedule<Double>(dailyItems: scheduleItems) else {
                            self.log.error("Failed to convert schedule")
                            completion(.failure(PumpManagerError.configuration(DanaKitPumpManagerError.failedBasalGeneration)))
                            return
                        }

                        self.state.basalDeliveryOrdinal = .active
                        self.state.basalDeliveryDate = Date.now
                        self.state.basalSchedule = basal
                        self.notifyStateDidChange()

                        let dose = DoseEntry.basal(rate: self.currentBaseBasalRate, insulinType: self.state.insulinType!)
                        self.pumpDelegate.notify { delegate in
                            guard let delegate = delegate else {
                                self.log.error("Basal could not be reported -> Missing delegate")
                                return
                            }

                            delegate.pumpManager(
                                self,
                                hasNewPumpEvents: [NewPumpEvent.basal(dose: dose)],
                                lastReconciliation: Date.now,
                                replacePendingEvents: true,
                                completion: { _ in }
                            )
                        }

                        completion(.success(schedule))
                    } catch {
                        self.disconnect()

                        self.log.error("Failed to suspend delivery. Error: \(error.localizedDescription)")
                        completion(.failure(
                            PumpManagerError
                                .communication(DanaKitPumpManagerError.unknown(error.localizedDescription))
                        ))
                    }
                default:
                    self.log.error("Connection error")
                    completion(.failure(PumpManagerError.connection(DanaKitPumpManagerError.noConnection(result))))
                    return
                }
            }
        }
    }

    public func setUserSettings(data: PacketGeneralSetUserOption, completion: @escaping (Bool) -> Void) {
        delegateQueue.async {
            self.log.info("Set user settings")

            self.bluetooth.ensureConnected { result in
                switch result {
                case .success:
                    do {
                        let packet = generatePacketGeneralSetUserOption(options: data)
                        let result = try await self.bluetooth.writeMessage(packet)

                        self.disconnect()
                        guard result.success else {
                            self.log.error("Pump rejected command (user options)")
                            completion(false)
                            return
                        }
                        completion(true)
                    } catch {
                        self.log.error("error caught \(error.localizedDescription)")
                        self.disconnect()
                        completion(false)
                    }
                default:
                    self.log.error("Connection error")
                    completion(false)
                    return
                }
            }
        }
    }

    public func syncDeliveryLimits(limits _: DeliveryLimits, completion: @escaping (Result<DeliveryLimits, Error>) -> Void) {
        delegateQueue.async {
            // Dana does not allow the max basal and max bolus to be set
            self.log.info("Skipping sync delivery limits (not supported by dana). Fetching current settings")

            self.bluetooth.ensureConnected { result in
                switch result {
                case .success:
                    do {
                        let basalPacket = generatePacketBasalGetRate()
                        let basalResult = try await self.bluetooth.writeMessage(basalPacket)

                        guard basalResult.success else {
                            self.log.error("Pump refused to send basal rates back")
                            self.disconnect()
                            completion(.failure(
                                PumpManagerError
                                    .configuration(DanaKitPumpManagerError.unknown("Pump refused to send basal rates back"))
                            ))
                            return
                        }

                        let bolusPacket = generatePacketBolusGetStepInformation()
                        let bolusResult = try await self.bluetooth.writeMessage(bolusPacket)

                        self.disconnect()
                        guard bolusResult.success else {
                            self.log.error("Pump refused to send bolus step back")
                            completion(.failure(
                                PumpManagerError
                                    .configuration(DanaKitPumpManagerError.unknown("Pump refused to send bolus step back"))
                            ))
                            return
                        }

                        self.log.info("Fetching pump settings succesfully!")
                        completion(.success(DeliveryLimits(
                            maximumBasalRate: HKQuantity(
                                unit: HKUnit.internationalUnit().unitDivided(by: .hour()),
                                doubleValue: (basalResult.data as! PacketBasalGetRate).maxBasal
                            ),
                            maximumBolus: HKQuantity(
                                unit: .internationalUnit(),
                                doubleValue: (bolusResult.data as! PacketBolusGetStepInformation).maxBolus
                            )
                        )))
                    } catch {
                        self.log.error("error caught \(error.localizedDescription)")
                        self.disconnect()
                        completion(.failure(
                            PumpManagerError
                                .communication(DanaKitPumpManagerError.unknown(error.localizedDescription))
                        ))
                    }
                default:
                    self.log.error("Connection error")
                    completion(.failure(PumpManagerError.connection(DanaKitPumpManagerError.noConnection(result))))
                    return
                }
            }
        }
    }

    public func syncPumpTime(completion: @escaping (Error?) -> Void) {
        delegateQueue.async {
            self.bluetooth.ensureConnected { result in
                switch result {
                case .success:
                    do {
                        let offset = Date.now.timeIntervalSince(self.state.pumpTime ?? Date.distantPast)
                        let packet: DanaGeneratePacket
                        if self.state.usingUtc {
                            let offsetInHours = round(Double(TimeZone.current.secondsFromGMT(for: Date.now) / 3600))
                            packet =
                                generatePacketGeneralSetPumpTimeUtcWithTimezone(options: PacketGeneralSetPumpTimeUtcWithTimezone(
                                    time: Date.now,
                                    zoneOffset: UInt8(truncatingIfNeeded: Int8(offsetInHours))
                                ))
                        } else {
                            packet = generatePacketGeneralSetPumpTime(options: PacketGeneralSetPumpTime(time: Date.now))
                        }

                        let result = try await self.bluetooth.writeMessage(packet)

                        let pumpTime = await self.fetchPumpTime()
                        if let pumpTime = pumpTime {
                            self.state.pumpTimeSyncedAt = Date.now
                            self.state.pumpTime = pumpTime
                        }

                        self.notifyStateDidChange()

                        self.disconnect()

                        guard result.success else {
                            self.log.error("Failed to sync pump time: Pump rejected command")
                            completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTimeAdjustment))
                            return
                        }

                        self.pumpDelegate.notify { delegate in
                            guard let delegate = delegate else {
                                self.log.error("Clock offset could not be reported -> Missing delegate")
                                return
                            }

                            delegate.pumpManager(self, didAdjustPumpClockBy: offset)
                        }
                        completion(nil)
                    } catch {
                        self.disconnect()
                        self.log.error("Failed to sync time. Error: \(error.localizedDescription)")
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                default:
                    self.log.error("Connection error")
                    completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection(result)))
                    return
                }
            }
        }
    }

    private func device() -> HKDevice {
        HKDevice(
            name: managerIdentifier,
            manufacturer: "Sooil",
            model: state.getFriendlyDeviceName(),
            hardwareVersion: String(state.hwModel),
            firmwareVersion: String(state.pumpProtocol),
            softwareVersion: "",
            localIdentifier: state.deviceName,
            udiDeviceIdentifier: nil
        )
    }

    private func absoluteBasalRateToPercentage(absoluteValue: Double, basalSchedule: [Double]) -> UInt16? {
        if absoluteValue == 0 {
            return 0
        }

        guard basalSchedule.count == 24 else {
            return nil
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let nowTimeInterval = now.timeIntervalSince(startOfDay)

        let basalIntervals: [TimeInterval] = Array(0 ..< 24).map({ TimeInterval(60 * 60 * $0) })
        let basalIndex = (basalIntervals.firstIndex(where: { $0 > nowTimeInterval }) ?? 24) - 1
        let basalRate = basalSchedule[basalIndex]

        return UInt16(round(absoluteValue / basalRate * 100))
    }
}

extension DanaKitPumpManager: AlertSoundVendor {
    public func getSoundBaseURL() -> URL? {
        nil
    }

    public func getSounds() -> [LoopKit.Alert.Sound] {
        []
    }
}

public extension DanaKitPumpManager {
    func acknowledgeAlert(alertIdentifier _: LoopKit.Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}

// MARK: State observers

public extension DanaKitPumpManager {
    func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }

    func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }

    func addStateObserver(_ observer: StateObserver, queue: DispatchQueue) {
        stateObservers.insert(observer, queue: queue)
    }

    func removeStateObserver(_ observer: StateObserver) {
        stateObservers.removeElement(observer)
    }

    func notifyStateDidChange() {
        DispatchQueue.main.async {
            let status = self.status(self.state)
            let oldStatus = self.status(self.oldState)

            self.stateObservers.forEach { observer in
                observer.stateDidUpdate(self.state, self.oldState)
            }

            self.pumpDelegate.notify { delegate in
                guard let delegate = delegate else {
                    self.log.error("State update could not be reported -> Missing delegate")
                    return
                }

                delegate.pumpManagerDidUpdateState(self)
                delegate.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
            }

            self.statusObservers.forEach { observer in
                observer.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
            }

            self.oldState = DanaKitPumpManagerState(rawValue: self.state.rawValue)
        }
    }

    func addScanDeviceObserver(_ observer: StateObserver, queue: DispatchQueue) {
        scanDeviceObservers.insert(observer, queue: queue)
    }

    func removeScanDeviceObserver(_ observer: StateObserver) {
        scanDeviceObservers.removeElement(observer)
    }

    internal func notifyAlert(_ alert: PumpManagerAlert) {
        let identifier = Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: alert.identifier)
        let loopAlert = Alert(
            identifier: identifier,
            foregroundContent: alert.foregroundContent,
            backgroundContent: alert.backgroundContent,
            trigger: .immediate
        )

        let event = NewPumpEvent(
            date: Date.now,
            dose: nil,
            raw: alert.raw,
            title: "Alarm: \(alert.foregroundContent.title)",
            type: .alarm,
            alarmType: alert.type
        )

        pumpDelegate.notify { delegate in
            guard let delegate = delegate else {
                self.log.error("Alarm could not be reported -> Missing delegate")
                return
            }

            delegate.issueAlert(loopAlert)
            delegate.pumpManager(
                self,
                hasNewPumpEvents: [event],
                lastReconciliation: Date.now,
                replacePendingEvents: true,
                completion: { _ in }
            )
        }
    }

    internal func notifyScanDeviceDidChange(_ device: DanaPumpScan) {
        DispatchQueue.main.async {
            self.scanDeviceObservers.forEach { observer in
                observer.deviceScanDidUpdate(device)
            }
        }
    }

    internal func notifyBolusError() {
        if let bolusCallback = self.bolusCallback {
            bolusCallback.resume()
            self.bolusCallback = nil
        }

        guard doseEntry != nil, state.bolusState != .noBolus else {
            // Ignore if no bolus is going
            return
        }

        doseEntry = nil
        doseReporter = nil
        state.bolusState = .noBolus
        state.lastStatusDate = Date.now
        notifyStateDidChange()
    }

    internal func notifyBolusDidUpdate(deliveredUnits: Double) {
        guard let doseEntry = self.doseEntry else {
            log.error("No bolus entry found...")
            return
        }

        doseEntry.deliveredUnits = deliveredUnits
        doseReporter?.notify(deliveredUnits: deliveredUnits)
        notifyStateDidChange()

        if deliveredUnits.truncatingRemainder(dividingBy: getDoseDivider()) == 0.0 {
            Task {
                do {
                    let command = generatePacketGeneralKeepConnection()
                    let result = try await bluetooth.writeMessage(command)

                    guard result.success else {
                        self.log.warning("Pump declined keepalive")
                        return
                    }

                    self.log.info("Pump accepted keepalive")
                } catch {
                    self.log.error("Failed to send keepalive: \(error)")
                }
            }
        }
    }

    private func getDoseDivider() -> Double {
        switch state.bolusSpeed {
        case .speed12:
            return 20.0
        case .speed30:
            return 8.0
        case .speed60:
            return 4.0
        }
    }

    internal func notifyBolusDone(deliveredUnits: Double) {
        Task {
            self.state.bolusState = .noBolus

            self.state.lastStatusPumpDateTime = await self.fetchPumpTime() ?? Date.now
            self.state.lastStatusDate = Date.now
            self.notifyStateDidChange()

            let work = DispatchWorkItem { [weak self] in
                self?.disconnect()
            }

            delegateQueue.asyncAfter(deadline: .now() + 1, execute: work)

            if let bolusCallback = self.bolusCallback {
                bolusCallback.resume()
                self.bolusCallback = nil
            }

            guard let doseEntry = self.doseEntry else {
                return
            }

            doseEntry.deliveredUnits = deliveredUnits

            let dose = doseEntry.toDoseEntry()
            self.doseEntry = nil
            self.doseReporter = nil

            guard !self.isPriming else {
                return
            }

            self.pumpDelegate.notify { delegate in
                guard let delegate = delegate else {
                    self.log.error("Dose could not be reported -> Missing delegate")
                    return
                }

                delegate.pumpManager(
                    self,
                    hasNewPumpEvents: [NewPumpEvent.bolus(dose: dose, units: deliveredUnits, date: dose.startDate)],
                    lastReconciliation: Date.now,
                    replacePendingEvents: true,
                    completion: { _ in }
                )
            }

            self.notifyStateDidChange()
        }
    }

    internal func checkBolusDone() {
        guard let doseEntry = self.doseEntry else {
            // Disconnect was done after bolus was complete!
            return
        }

        if let bolusCallback = self.bolusCallback {
            bolusCallback.resume()
            self.bolusCallback = nil
        }

        log.warning("Bolus was not completed... \(doseEntry.deliveredUnits)U of the \(doseEntry.value)U")

        // There was a bolus going on, unsure if the bolus is completed...
        state.bolusState = .noBolus
        state.lastStatusDate = Date.now
        self.doseEntry = nil
        notifyStateDidChange()

        pumpDelegate.notify { delegate in
            guard let delegate = delegate else {
                self.log.error("Uncertain delivery could not be reported -> Missing delegate")
                return
            }

            delegate.pumpManager(self, didError: .uncertainDelivery)
        }
    }
}
