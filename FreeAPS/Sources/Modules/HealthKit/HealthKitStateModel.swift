import Combine
import SwiftUI

extension AppleHealthKit {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var healthKitManager: HealthKitManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var useAppleHealth = false
        @Published var needShowInformationTextForSetPermissions = false

        override func subscribe() {
            units = settingsManager.settings.units

            useAppleHealth = settingsManager.settings.useAppleHealth

            needShowInformationTextForSetPermissions = healthKitManager.areAllowAllPermissions

            subscribeSetting(\.useAppleHealth, on: $useAppleHealth) {
                useAppleHealth = $0
            } didSet: { [weak self] value in
                guard let self = self else { return }

                guard value else {
                    self.needShowInformationTextForSetPermissions = false
                    return
                }

                self.healthKitManager.requestPermission { ok, error in
                    DispatchQueue.main.async {
                        self.needShowInformationTextForSetPermissions = !self.healthKitManager.checkAvailabilitySaveBG()
                    }

                    guard ok, error == nil else {
                        warning(.service, "Permission not granted for HealthKitManager", error: error)
                        return
                    }

                    debug(.service, "Permission  granted HealthKitManager")

                    self.healthKitManager.createBGObserver()
                    self.healthKitManager.enableBackgroundDelivery()
                }
            }
        }
    }
}

extension AppleHealthKit.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
