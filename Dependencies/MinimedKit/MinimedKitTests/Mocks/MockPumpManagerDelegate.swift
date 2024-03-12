//
//  MockPumpManagerDelegate.swift
//  MinimedKitTests
//
//  Created by Pete Schwamb on 9/5/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

class MockPumpManagerDelegate: PumpManagerDelegate {
    var automaticDosingEnabled = true

    var historyFetchStartDate = Date()

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {}

    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool {
        return false
    }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {}

    func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager) {}

    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {}

    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {}

    var reportedPumpEvents: [(events: [NewPumpEvent], lastReconciliation: Date?)] = []
    
    func pumpManager(_ pumpManager: PumpManager, hasNewPumpEvents events: [NewPumpEvent], lastReconciliation: Date?, replacePendingEvents: Bool, completion: @escaping (Error?) -> Void) {
        reportedPumpEvents.append((events: events, lastReconciliation: lastReconciliation))
        completion(nil)
    }

    struct MockReservoirValue: ReservoirValue {
        let startDate: Date
        let unitVolume: Double
    }

    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date, completion: @escaping (Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) -> Void)
    {
        let reservoirValue = MockReservoirValue(startDate: date, unitVolume: units)
        DispatchQueue.main.async {
            completion(.success((newValue: reservoirValue, lastValue: nil, areStoredValuesContinuous: true)))
        }
    }

    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {}

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {}
    
    func pumpManager(_ pumpManager: PumpManager, didRequestBasalRateScheduleChange basalRateSchedule: BasalRateSchedule, completion: @escaping (Error?) -> Void) { }

    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        return historyFetchStartDate
    }

    var detectedSystemTimeOffset: TimeInterval = 0

    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {}

    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {}

    func issueAlert(_ alert: Alert) {}

    func retractAlert(identifier: Alert.Identifier) {}

    func doesIssuedAlertExist(identifier: Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {}

    func lookupAllUnretracted(managerIdentifier: String, completion: @escaping (Result<[PersistedAlert], Error>) -> Void) {}

    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String, completion: @escaping (Result<[PersistedAlert], Error>) -> Void) {}

    func recordRetractedAlert(_ alert: Alert, at date: Date) {}

}
