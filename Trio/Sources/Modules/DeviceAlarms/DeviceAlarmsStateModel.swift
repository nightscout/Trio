import Combine
import LoopKit
import SwiftUI

extension DeviceAlarms {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceDataManager: DeviceDataManager!
        @Injected() var fetchGlucoseManager: FetchGlucoseManager!

        /// Alerts the paired pump and CGM, and Trio itself, can issue under the device tiers.
        var issuableAlerts: [IssuableAlert] {
            var alerts = BaseTrioAlertManager.tierConfiguredAlerts
            if let pump = deviceDataManager.pumpManager {
                alerts += type(of: pump).issuableAlerts
            }
            if let cgm = fetchGlucoseManager.cgmManager {
                alerts += type(of: cgm).issuableAlerts
            }
            return alerts
        }

        override func subscribe() {}
    }
}
