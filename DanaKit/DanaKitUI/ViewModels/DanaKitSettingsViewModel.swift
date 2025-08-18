import HealthKit
import LoopKit
import SwiftUI

class DanaKitSettingsViewModel: ObservableObject {
    @Published var showingDeleteConfirmation = false
    @Published var showingBleModeSwitch = false
    @Published var showingTimeSyncConfirmation = false
    @Published var showingDisconnectReminder = false
    @Published var showingBolusSyncingDisabled = false
    @Published var showingBlindReservoirCannulaRefill = false
    @Published var basalButtonText: String = ""
    @Published var bolusSpeed: BolusSpeed
    @Published var isUsingContinuousMode: Bool = false
    @Published var isUpdatingPumpState: Bool = false
    @Published var isConnected: Bool = false
    @Published var isTogglingConnection: Bool = false
    @Published var isBolusSyncingDisabled = false
    @Published var isSyncing: Bool = false
    @Published var lastSync: Date? = nil
    @Published var batteryLevel: Double = 0
    @Published var showingSilentTone: Bool = false
    @Published var silentTone: Bool = false
    @Published var basalProfileNumber: UInt8 = 0
    @Published var cannulaAge: String? = nil
    @Published var reservoirAge: String? = nil
    @Published var batteryAge: String? = nil

    @Published var showPumpTimeSyncWarning: Bool = false
    @Published var pumpTime: Date? = nil
    @Published var pumpTimeSyncedAt: Date? = nil
    @Published var nightlyPumpTimeSync: Bool = false

    @Published var reservoirLevelWarning: Double
    @Published var reservoirLevel: Double?
    @Published var isSuspended: Bool = false
    @Published var basalRate: Double?
    @Published var showingReservoirCannulaRefillView: Bool = false

    private let log = DanaLogger(category: "SettingsView")
    private(set) var insulinType: InsulinType
    private(set) var pumpManager: DanaKitPumpManager?
    private var didFinish: (() -> Void)?
    private(set) var userOptionsView: DanaKitUserSettingsView
    private(set) var refillView: DanaKitRefillReservoirAndCannulaView

    public var pumpModel: String {
        pumpManager?.state.getFriendlyDeviceName() ?? ""
    }

    public var deviceName: String? {
        pumpManager?.state.deviceName
    }

    public var hardwareModel: UInt8? {
        pumpManager?.state.hwModel
    }

    public var firmwareVersion: UInt8? {
        pumpManager?.state.pumpProtocol
    }

    public var isTempBasal: Bool {
        guard let pumpManager = self.pumpManager else {
            return false
        }

        return pumpManager.state.basalDeliveryOrdinal == .tempBasal && pumpManager.state.tempBasalEndsAt > Date.now
    }

    let basalRateFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.minimumIntegerDigits = 1
        return numberFormatter
    }()

    let reservoirVolumeFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit())
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()

    private let dateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    public init(_ pumpManager: DanaKitPumpManager?, _ didFinish: (() -> Void)?) {
        self.pumpManager = pumpManager
        self.didFinish = didFinish

        userOptionsView = DanaKitUserSettingsView(viewModel: DanaKitUserSettingsViewModel(self.pumpManager))
        refillView =
            DanaKitRefillReservoirAndCannulaView(viewModel: DanaKitRefillReservoirCannulaViewModel(
                pumpManager: pumpManager,
                cannulaOnly: false
            ))

        isUsingContinuousMode = self.pumpManager?.state.isUsingContinuousMode ?? false
        isConnected = self.pumpManager?.state.isConnected ?? false
        insulinType = self.pumpManager?.state.insulinType ?? .novolog
        bolusSpeed = self.pumpManager?.state.bolusSpeed ?? .speed12
        lastSync = self.pumpManager?.state.lastStatusDate
        reservoirLevel = self.pumpManager?.state.reservoirLevel
        isSuspended = self.pumpManager?.state.isPumpSuspended ?? false
        pumpTime = self.pumpManager?.state.pumpTime
        pumpTimeSyncedAt = self.pumpManager?.state.pumpTimeSyncedAt
        nightlyPumpTimeSync = self.pumpManager?.state.allowAutomaticTimeSync ?? false
        isBolusSyncingDisabled = self.pumpManager?.state.isBolusSyncDisabled ?? false
        batteryLevel = self.pumpManager?.state.batteryRemaining ?? 0
        silentTone = self.pumpManager?.state.useSilentTones ?? false
        reservoirLevelWarning = Double(self.pumpManager?.state.lowReservoirRate ?? 20)
        basalProfileNumber = self.pumpManager?.state.basalProfileNumber ?? 0
        showPumpTimeSyncWarning = self.pumpManager?.state.shouldShowTimeWarning() ?? false
        updateBasalRate()

        if let cannulaDate = self.pumpManager?.state.cannulaDate {
            cannulaAge = formatDateToDayHour(cannulaDate)
        }

        if let reservoirDate = self.pumpManager?.state.reservoirDate {
            reservoirAge = formatDateToDayHour(reservoirDate)
        }

        if let batteryDate = self.pumpManager?.state.batteryAge {
            batteryAge = formatDateToDayHour(batteryDate)
        }

        basalButtonText = updateBasalButtonText()

        self.pumpManager?.addStateObserver(self, queue: .main)
    }

    func stopUsingDana() {
        pumpManager?.notifyDelegateOfDeactivation {
            DispatchQueue.main.async {
                self.didFinish?()
            }
        }
    }

    func updateReservoirAge() {
        pumpManager?.state.reservoirDate = Date.now
        reservoirAge = formatDateToDayHour(Date.now)
        pumpManager?.notifyStateDidChange()
    }

    func updateCannulaAge() {
        pumpManager?.state.cannulaDate = Date.now
        cannulaAge = formatDateToDayHour(Date.now)
        pumpManager?.notifyStateDidChange()
    }

    func updateBatteryAge() {
        pumpManager?.state.batteryAge = Date.now
        batteryAge = formatDateToDayHour(Date.now)
        pumpManager?.notifyStateDidChange()
    }

    func scheduleDisconnectNotification(_ duration: TimeInterval) {
        NotificationHelper.setDisconnectReminder(duration)
        pumpManager?.disconnect(true)
    }

    func navigateToRefillView(_ cannulaOnly: Bool) {
        refillView =
            DanaKitRefillReservoirAndCannulaView(viewModel: DanaKitRefillReservoirCannulaViewModel(
                pumpManager: pumpManager,
                cannulaOnly: cannulaOnly
            ))
        showingReservoirCannulaRefillView = true
    }

    func forceDisconnect() {
        pumpManager?.disconnect(true)
    }

    func didChangeInsulinType(_ newType: InsulinType?) {
        guard let type = newType else {
            return
        }

        pumpManager?.state.insulinType = type
        pumpManager?.notifyStateDidChange()
        insulinType = type
    }

    func getLogs() -> [URL] {
        if let pumpManager = self.pumpManager {
            log.info(pumpManager.state.debugDescription)
        }
        return log.getDebugLogs()
    }

    func toggleBleMode() {
        pumpManager?.toggleBluetoothMode()
        isTogglingConnection = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.isTogglingConnection = false
        }
    }

    func reconnect() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        isTogglingConnection = true
        pumpManager.reconnect { _ in
            DispatchQueue.main.async {
                self.isTogglingConnection = false
            }
        }
    }

    func formatDate(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }

        return dateFormatter.string(from: date)
    }

    func didBolusSpeedChanged(_ bolusSpeed: BolusSpeed) {
        pumpManager?.state.bolusSpeed = bolusSpeed
        pumpManager?.notifyStateDidChange()
        self.bolusSpeed = bolusSpeed
    }

    func syncData() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        DispatchQueue.main.async {
            self.isSyncing = true
        }

        pumpManager.syncPump { date in
            DispatchQueue.main.async {
                self.isSyncing = false

                if let date = date {
                    self.lastSync = date
                }
            }
        }
    }

    func updateNightlyPumpTimeSync(_ value: Bool) {
        guard let pumpManager = self.pumpManager else {
            return
        }

        pumpManager.state.allowAutomaticTimeSync = value
        pumpManager.notifyStateDidChange()
    }

    func syncPumpTime() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        isSyncing = true
        pumpManager.syncPumpTime { _ in
            DispatchQueue.main.async {
                self.isSyncing = false
            }
        }
    }

    func reservoirText(for units: Double) -> String {
        let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: units)
        return reservoirVolumeFormatter.string(from: quantity) ?? ""
    }

    func toggleSilentTone() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        pumpManager.state.useSilentTones = !silentTone
        silentTone = pumpManager.state.useSilentTones
    }

    func toggleBolusSyncing() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        pumpManager.state.isBolusSyncDisabled = !isBolusSyncingDisabled
        pumpManager.notifyStateDidChange()
    }

    func transformBasalProfile(_ index: UInt8) -> String {
        if index == 0 {
            return "A"
        } else if index == 1 {
            return "B"
        } else if index == 2 {
            return "C"
        } else {
            return "D"
        }
    }

    func stopTempBasal() {
        if isTempBasal {
            isUpdatingPumpState = true

            // Stop temp basal
            pumpManager?.enactTempBasal(unitsPerHour: 0, for: 0, completion: { error in
                DispatchQueue.main.async {
                    self.basalButtonText = self.updateBasalButtonText()
                    self.isUpdatingPumpState = false
                }

                // Check if action failed, otherwise skip state sync
                guard error == nil else {
                    self.log.error("\(#function): failed to stop temp basal. Error: \(error!.localizedDescription)")
                    return
                }
            })

            return
        }
    }

    func suspendResumeButtonPressed() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        isUpdatingPumpState = true

        if pumpManager.state.isPumpSuspended {
            self.pumpManager?.resumeDelivery { error in
                DispatchQueue.main.async {
                    self.basalButtonText = self.updateBasalButtonText()
                    self.isUpdatingPumpState = false
                }

                // Check if action failed, otherwise skip state sync
                guard error == nil else {
                    self.log.error("\(#function): failed to resume delivery. Error: \(error!.localizedDescription)")
                    return
                }
            }

            return
        }

        pumpManager.suspendDelivery(completion: { error in
            DispatchQueue.main.async {
                self.basalButtonText = self.updateBasalButtonText()
                self.isUpdatingPumpState = false
            }

            // Check if action failed, otherwise skip state sync
            guard error == nil else {
                self.log.error("\(#function): failed to suspend delivery. Error: \(error!.localizedDescription)")
                return
            }
        })
    }

    private func updateBasalButtonText() -> String {
        guard let pumpManager = self.pumpManager else {
            return LocalizedString("Suspend delivery", comment: "Dana settings suspend delivery")
        }

        if pumpManager.state.isPumpSuspended {
            return LocalizedString("Resume delivery", comment: "Dana settings resume delivery")
        }

        return LocalizedString("Suspend delivery", comment: "Dana settings suspend delivery")
    }

    private func updateBasalRate() {
        guard let pumpManager = self.pumpManager else {
            basalRate = 0
            return
        }

        if pumpManager.state.basalDeliveryOrdinal == .tempBasal, pumpManager.state.tempBasalEndsAt > Date.now {
            basalRate = pumpManager.state.tempBasalUnits ?? pumpManager.currentBaseBasalRate
        } else {
            basalRate = pumpManager.currentBaseBasalRate
        }
    }

    private func formatDateToDayHour(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: date, to: Date.now)
        if let days = components.day, let hours = components.hour {
            return "\(days)d \(hours)h"
        }

        return "?d ?h"
    }
}

extension DanaKitSettingsViewModel: StateObserver {
    func stateDidUpdate(_ state: DanaKitPumpManagerState, _: DanaKitPumpManagerState) {
        isUsingContinuousMode = state.isUsingContinuousMode
        isConnected = state.isConnected
        insulinType = state.insulinType ?? .novolog
        bolusSpeed = state.bolusSpeed
        lastSync = state.lastStatusDate
        reservoirLevel = state.reservoirLevel
        isSuspended = state.isPumpSuspended
        isBolusSyncingDisabled = state.isBolusSyncDisabled
        pumpTime = state.pumpTime
        pumpTimeSyncedAt = state.pumpTimeSyncedAt
        nightlyPumpTimeSync = state.allowAutomaticTimeSync
        batteryLevel = state.batteryRemaining
        silentTone = state.useSilentTones
        basalProfileNumber = state.basalProfileNumber
        showPumpTimeSyncWarning = state.shouldShowTimeWarning()
        updateBasalRate()

        basalButtonText = updateBasalButtonText()

        if let cannulaDate = state.cannulaDate {
            cannulaAge = formatDateToDayHour(cannulaDate)
        }

        if let reservoirDate = state.reservoirDate {
            reservoirAge = formatDateToDayHour(reservoirDate)
        }

        if let batteryAge = state.batteryAge {
            self.batteryAge = formatDateToDayHour(batteryAge)
        }
    }

    func deviceScanDidUpdate(_: DanaPumpScan) {
        // Don't do anything here. We are not scanning for a new pump
    }
}
