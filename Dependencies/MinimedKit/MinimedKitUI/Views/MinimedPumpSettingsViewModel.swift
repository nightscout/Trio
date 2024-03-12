//
//  MinimedPumpSettingsViewModel.swift
//  MinimedKitUI
//
//  Created by Pete Schwamb on 11/29/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import MinimedKit
import LoopKit
import SwiftUI
import LoopKitUI
import HealthKit


enum MinimedSettingsViewAlert: Identifiable {
    case suspendError(Error)
    case resumeError(Error)
    case syncTimeError(PumpManagerError)

    var id: String {
        switch self {
        case .suspendError:
            return "suspendError"
        case .resumeError:
            return "resumeError"
        case .syncTimeError:
            return "syncTimeError"
        }
    }
}

enum MySentryConfig: Int, Identifiable, CaseIterable {
    var id: RawValue {
        return self.rawValue
    }

    case useMySentry = 0
    case doNotUseMySentry

    var localizedDescription: String {
        switch self {
        case .useMySentry:
            return LocalizedString("Use MySentry", comment: "Description for option to use MySentry")
        case .doNotUseMySentry:
            return LocalizedString("Do not use MySentry", comment: "Description for option to not use MySentry")
        }
    }
}

public enum ReservoirLevelHighlightState: String, Equatable {
    case normal
    case warning
    case critical
}

class MinimedPumpSettingsViewModel: ObservableObject {

    @Published var suspendResumeTransitioning: Bool = false
    @Published var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    @Published var reservoirReading: ReservoirReading?

    @Published var batteryChemistryType: BatteryChemistryType {
        didSet {
            pumpManager.batteryChemistry = batteryChemistryType
        }
    }

    @Published var preferredDataSource: InsulinDataSource {
        didSet {
            pumpManager.preferredInsulinDataSource = preferredDataSource
        }
    }

    @Published var mySentryConfig: MySentryConfig {
        didSet {
            pumpManager.useMySentry = mySentryConfig == .useMySentry
        }
    }

    @Published var activeAlert: MinimedSettingsViewAlert?
    @Published var suspendResumeButtonEnabled: Bool = false
    @Published var synchronizingTime: Bool = false

    var pumpManager: MinimedPumpManager

    var didFinish: (() -> Void)?

    let basalRateFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.minimumIntegerDigits = 1
        return numberFormatter
    }()

    let reservoirVolumeFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit())
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()

    init(pumpManager: MinimedPumpManager) {
        self.pumpManager = pumpManager
        self.basalDeliveryState = pumpManager.status.basalDeliveryState
        self.reservoirReading = pumpManager.state.lastReservoirReading
        self.batteryChemistryType = pumpManager.batteryChemistry
        self.preferredDataSource = pumpManager.preferredInsulinDataSource
        self.mySentryConfig = pumpManager.useMySentry ? .useMySentry : .doNotUseMySentry

        self.pumpManager.addStatusObserver(self, queue: DispatchQueue.main)
        pumpManager.stateObservers.insert(self, queue: .main)
    }

    var pumpImage: UIImage {
        return pumpManager.state.largePumpImage
    }

    func deletePump() {
        pumpManager.deletePump {
            DispatchQueue.main.async {
                self.didFinish?()
            }
        }
    }

    func doneButtonPressed() {
        self.didFinish?()
    }

    func suspendResumeButtonPressed(action: SuspendResumeAction) {
        suspendResumeButtonEnabled = true
        switch action {
        case .resume:
            pumpManager.resumeDelivery { error in
                DispatchQueue.main.async {
                    self.suspendResumeButtonEnabled = false
                    if let error = error {
                        self.activeAlert = .resumeError(error)
                    }
                }
            }
        case .suspend:
            pumpManager.suspendDelivery { error in
                DispatchQueue.main.async {
                    self.suspendResumeButtonEnabled = false
                    if let error = error {
                        self.activeAlert = .suspendError(error)
                    }
                }
            }
        }
    }

    func didChangeInsulinType(_ newType: InsulinType?) {
        self.pumpManager.insulinType = newType
    }

    var isScheduledBasal: Bool {
        switch basalDeliveryState {
        case .active(_), .initiatingTempBasal:
            return true
        case .tempBasal(_), .cancelingTempBasal, .suspending, .suspended(_), .resuming, .none:
            return false
        }
    }

    var isSuspendedOrResuming: Bool {
        switch basalDeliveryState {
        case .suspended, .resuming:
            return true
        default:
            return false
        }
    }

    func suspendResumeButtonColor(guidanceColors: GuidanceColors) -> Color {
        switch basalDeliveryState {
        case .suspending, .resuming:
            return Color.secondary
        case .suspended:
            return guidanceColors.warning
        default:
            return .accentColor
        }
    }

    var basalDeliveryRate: Double? {
        switch basalDeliveryState {
        case .suspending, .resuming, .suspended, .none, .initiatingTempBasal, .cancelingTempBasal:
            return nil
        case .active:
            // return scheduled basal rate
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = pumpManager.state.timeZone
            return pumpManager.state.basalSchedule.currentRate(using: calendar)
        case .tempBasal(let dose):
            return dose.unitsPerHour
        }
    }

    public var reservoirLevelHighlightState: ReservoirLevelHighlightState? {
        guard let reservoirReading = reservoirReading else {
            return nil
        }

        let value = reservoirReading.units

        if value > pumpManager.lowReservoirWarningLevel {
            return .normal
        } else if value > 0 {
            return .warning
        } else {
            return .critical
        }
    }

    public var reservoirPercentage: Double? {
        guard let reservoirReading = reservoirReading else {
            return nil
        }

        return (reservoirReading.units / pumpManager.pumpReservoirCapacity).clamped(to: 0...1.0)
    }

    func reservoirText(for units: Double) -> String {
        let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: units)
        return reservoirVolumeFormatter.string(from: quantity) ?? ""
    }

    var isClockOffset: Bool {
        return pumpManager.isClockOffset
    }

    func changeTimeZoneTapped() {
        synchronizingTime = true
        pumpManager.setTime { (error) in
            DispatchQueue.main.async {
                self.synchronizingTime = false
                if let error = error {
                    self.activeAlert = .syncTimeError(error)
                }
            }
        }
    }

}

extension MinimedPumpSettingsViewModel: PumpManagerStatusObserver {
    public func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        basalDeliveryState = status.basalDeliveryState
    }
}

extension MinimedPumpSettingsViewModel: MinimedPumpManagerStateObserver {
    func didUpdatePumpManagerState(_ state: MinimedKit.MinimedPumpManagerState) {
        reservoirReading = state.lastReservoirReading
        batteryChemistryType = state.batteryChemistry
        preferredDataSource = state.preferredInsulinDataSource
        mySentryConfig = state.useMySentry ? .useMySentry : .doNotUseMySentry
    }
}


enum SuspendResumeAction {
    case suspend
    case resume
}

extension PumpManagerStatus.BasalDeliveryState {


    var shownAction: SuspendResumeAction {
        switch self {
        case .active, .suspending, .tempBasal, .cancelingTempBasal, .initiatingTempBasal:
            return .suspend
        case .suspended, .resuming:
            return .resume
        }
    }

    var buttonLabelText: String {
        switch self {
        case .active, .tempBasal:
            return LocalizedString("Suspend Delivery", comment: "Title text for button to suspend insulin delivery")
        case .suspending:
            return LocalizedString("Suspending", comment: "Title text for button when insulin delivery is in the process of being stopped")
        case .suspended:
            return LocalizedString("Resume Delivery", comment: "Title text for button to resume insulin delivery")
        case .resuming:
            return LocalizedString("Resuming", comment: "Title text for button when insulin delivery is in the process of being resumed")
        case .initiatingTempBasal:
            return LocalizedString("Starting Temp Basal", comment: "Title text for suspend resume button when temp basal starting")
        case .cancelingTempBasal:
            return LocalizedString("Canceling Temp Basal", comment: "Title text for suspend resume button when temp basal canceling")
        }
    }

    var isTransitioning: Bool {
        switch self {
        case .suspending, .resuming, .initiatingTempBasal, .cancelingTempBasal:
            return true
        default:
            return false
        }
    }

}
