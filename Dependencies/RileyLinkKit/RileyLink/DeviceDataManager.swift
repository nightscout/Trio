//
//  DeviceDataManager.swift
//  RileyLink
//
//  Created by Pete Schwamb on 4/27/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation
import RileyLinkKit
import RileyLinkKitUI
import RileyLinkBLEKit
import MinimedKit
import MinimedKitUI
import NightscoutKit
import LoopKit
import LoopKitUI
import UserNotifications
import os.log
import UserNotifications

class DeviceDataManager {

    let rileyLinkDeviceProvider: RileyLinkDeviceProvider
    
    var pumpManager: PumpManagerUI? {
        didSet {
            pumpManager?.pumpManagerDelegate = self
            UserDefaults.standard.pumpManagerRawValue = pumpManager?.rawValue
        }
    }
    

    public let log = OSLog(category: "DeviceDataManager")
    
    init() {
        
        let connectionManagerState = UserDefaults.standard.rileyLinkConnectionManagerState
        rileyLinkDeviceProvider = RileyLinkBluetoothDeviceProvider(autoConnectIDs: connectionManagerState?.autoConnectIDs ?? [])
        rileyLinkDeviceProvider.delegate = self
        rileyLinkDeviceProvider.setScanningEnabled(true)

        if let pumpManagerRawValue = UserDefaults.standard.pumpManagerRawValue {
            pumpManager = PumpManagerFromRawValue(pumpManagerRawValue, rileyLinkDeviceProvider: rileyLinkDeviceProvider) as? PumpManagerUI
            pumpManager?.pumpManagerDelegate = self
        }
    }
}

extension DeviceDataManager: RileyLinkDeviceProviderDelegate {
    func rileylinkDeviceProvider(_ rileylinkDeviceProvider: RileyLinkBLEKit.RileyLinkDeviceProvider, didChange state: RileyLinkBLEKit.RileyLinkConnectionState) {
        UserDefaults.standard.rileyLinkConnectionManagerState = state
    }
}

extension DeviceDataManager: PumpManagerDelegate {
    func pumpManagerPumpWasReplaced(_ pumpManager: LoopKit.PumpManager) {
    }

    var detectedSystemTimeOffset: TimeInterval {
        return 0;
    }

    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        log.debug("didAdjustPumpClockBy %@", adjustment)
    }
    
    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        UserDefaults.standard.pumpManagerRawValue = pumpManager.rawValue
    }
    
    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
    }
    
    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool {
        return true
    }
    
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
    }
    
    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        self.pumpManager = nil
    }
    
    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {
    }
    
    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {
        log.error("pumpManager didError %@", String(describing: error))
    }
    
    func pumpManager(_ pumpManager: PumpManager, hasNewPumpEvents events: [NewPumpEvent], lastSync lastReconciliation: Date?, completion: @escaping (_ error: Error?) -> Void) {
    }
    
    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date, completion: @escaping (Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) -> Void) {
    }

    func pumpManagerRecommendsLoop(_ pumpManager: PumpManager) {
    }
    
    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        return Date().addingTimeInterval(.hours(-2))
    }
}

// MARK: - DeviceManagerDelegate
extension DeviceDataManager: DeviceManagerDelegate {
    func doesIssuedAlertExist(identifier: LoopKit.Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
    }

    func lookupAllUnretracted(managerIdentifier: String, completion: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void) {
    }

    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String, completion: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void) {
    }

    func recordRetractedAlert(_ alert: LoopKit.Alert, at date: Date) {
    }

    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {}
}

// MARK: - AlertPresenter
extension DeviceDataManager: AlertIssuer {
    func issueAlert(_ alert: Alert) {
    }
    
    func retractAlert(identifier: Alert.Identifier) {
    }
}
