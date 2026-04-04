import Combine
import SwiftUI

extension AppleHealthKit {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var healthKitManager: HealthKitManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var useAppleHealth = false
        @Published var importMealsFromAppleHealth = false
        @Published var needShowInformationTextForSetPermissions = false

        override func subscribe() {
            units = settingsManager.settings.units

            useAppleHealth = settingsManager.settings.useAppleHealth
            importMealsFromAppleHealth = settingsManager.settings.importMealsFromAppleHealth

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

            subscribeSetting(\.importMealsFromAppleHealth, on: $importMealsFromAppleHealth) {
                importMealsFromAppleHealth = $0
            } didSet: { [weak self] value in
                guard let self = self, value else { return }
                // Trigger an immediate import when the user enables the setting
                Task {
                    await self.healthKitManager.importMealsFromHealth(since: self.syncDate())
                }
            }
        }

        /// Look-back window for the initial import: last 24 hours.
        private func syncDate() -> Date {
            Date().addingTimeInterval(-24 * 60 * 60)
        }
    }
}

extension AppleHealthKit.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
