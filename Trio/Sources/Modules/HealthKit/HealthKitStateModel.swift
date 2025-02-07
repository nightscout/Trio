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

            needShowInformationTextForSetPermissions = healthKitManager.hasGrantedFullWritePermissions

            subscribeSetting(\.useAppleHealth, on: $useAppleHealth) {
                useAppleHealth = $0
            } didSet: { [weak self] value in
                guard let self = self else { return }

                guard value else {
                    self.needShowInformationTextForSetPermissions = false
                    return
                }

                Task {
                    do {
                        let permissionGranted = try await self.healthKitManager.requestPermission()

                        await MainActor.run {
                            self.needShowInformationTextForSetPermissions = !self.healthKitManager.hasGlucoseWritePermission()
                        }

                        if permissionGranted {
                            debug(.service, "Permission granted for HealthKitManager")
                        } else {
                            warning(.service, "Permission not granted for HealthKitManager")
                        }
                    } catch {
                        warning(.service, "Error requesting permission for HealthKitManager", error: error)
                    }
                }
            }
        }
    }
}

extension AppleHealthKit.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
