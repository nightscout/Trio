import Combine
import SwiftUI

extension AppleHealthKit {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var healthKitManager: HealthKitManager!
        @Injected() var healthMetricsService: HealthMetricsService!

        @Published var units: GlucoseUnits = .mgdL
        @Published var useAppleHealth = false
        @Published var needShowInformationTextForSetPermissions = false

        // Health Metrics Settings for AI Analysis
        @Published var enableActivityData = false
        @Published var enableSleepData = false
        @Published var enableHeartRateData = false
        @Published var enableWorkoutData = false

        override func subscribe() {
            units = settingsManager.settings.units

            useAppleHealth = settingsManager.settings.useAppleHealth

            // Load health metrics settings
            enableActivityData = settingsManager.settings.healthMetricsSettings.enableActivityData
            enableSleepData = settingsManager.settings.healthMetricsSettings.enableSleepData
            enableHeartRateData = settingsManager.settings.healthMetricsSettings.enableHeartRateData
            enableWorkoutData = settingsManager.settings.healthMetricsSettings.enableWorkoutData

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

            // Subscribe to health metrics settings
            subscribeHealthMetricsSetting(\.enableActivityData, on: $enableActivityData) { [weak self] value in
                self?.requestHealthMetricsPermissionsIfNeeded()
            }

            subscribeHealthMetricsSetting(\.enableSleepData, on: $enableSleepData) { [weak self] _ in
                self?.requestHealthMetricsPermissionsIfNeeded()
            }

            subscribeHealthMetricsSetting(\.enableHeartRateData, on: $enableHeartRateData) { [weak self] _ in
                self?.requestHealthMetricsPermissionsIfNeeded()
            }

            subscribeHealthMetricsSetting(\.enableWorkoutData, on: $enableWorkoutData) { [weak self] _ in
                self?.requestHealthMetricsPermissionsIfNeeded()
            }
        }

        private func subscribeHealthMetricsSetting<T: Equatable>(
            _ keyPath: WritableKeyPath<HealthMetricsSettings, T>,
            on publisher: Published<T>.Publisher,
            didSet: @escaping (T) -> Void = { _ in }
        ) {
            publisher
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] newValue in
                    guard let self = self else { return }
                    var settings = self.settingsManager.settings.healthMetricsSettings
                    settings[keyPath: keyPath] = newValue
                    self.settingsManager.settings.healthMetricsSettings = settings
                    didSet(newValue)
                }
                .store(in: &lifetime)
        }

        private func requestHealthMetricsPermissionsIfNeeded() {
            let settings = settingsManager.settings.healthMetricsSettings
            guard settings.hasAnyEnabled else { return }

            Task {
                let granted = await healthMetricsService.requestPermissions()
                if granted {
                    debug(.service, "Health metrics permissions granted")
                } else {
                    warning(.service, "Health metrics permissions not fully granted")
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
