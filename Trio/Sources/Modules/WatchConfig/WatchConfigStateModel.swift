import Combine
import ConnectIQ
import SwiftUI

extension WatchConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var garmin: GarminManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var devices: [IQDevice] = []
        @Published var confirmBolusFaster = false

        /// Garmin watch settings containing all watch-related configuration
        @Published var garminSettings = GarminWatchSettings()

        /// Indicates if the enable/disable toggle is locked during cooldown period
        @Published var isWatchfaceDataCooldownActive: Bool = false

        /// Remaining seconds in the cooldown period
        @Published var watchfaceSwitchCooldownSeconds: Int = 0

        private(set) var preferences = Preferences()

        /// Timer for managing the 20-second cooldown after watchface changes
        private var watchfaceSwitchTimer: Timer?

        /// The timestamp when the current cooldown period will end
        private var watchfaceSwitchCooldownEndTime: Date?

        override func subscribe() {
            preferences = provider.preferences
            units = settingsManager.settings.units

            // Subscribe to the entire garminSettings struct from TrioSettings
            subscribeSetting(\.garminSettings, on: $garminSettings) { garminSettings = $0 }
            subscribeSetting(\.confirmBolusFaster, on: $confirmBolusFaster) { confirmBolusFaster = $0 }

            devices = garmin.devices
        }

        /// Prompts the user to select Garmin devices and updates the device list
        func selectGarminDevices() {
            garmin.selectDevices()
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.devices, on: self)
                .store(in: &lifetime)
        }

        /// Updates the Garmin manager with the current device list
        func deleteGarminDevice() {
            garmin.updateDeviceList(devices)
        }

        /// Handles watchface selection changes by automatically disabling data transmission
        /// and starting a 20-second cooldown period to allow the user to switch watchfaces
        /// on their Garmin device without data conflicts
        func handleWatchfaceChange() {
            garminSettings.isWatchfaceDataEnabled = false
            startCooldownTimer()
        }

        /// Starts a 20-second countdown timer that locks the enable/disable toggle and updates
        /// the remaining seconds display every second until the cooldown period expires
        private func startCooldownTimer() {
            watchfaceSwitchTimer?.invalidate()

            watchfaceSwitchCooldownEndTime = Date().addingTimeInterval(20)
            isWatchfaceDataCooldownActive = true
            watchfaceSwitchCooldownSeconds = 20

            watchfaceSwitchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }

                if let endTime = self.watchfaceSwitchCooldownEndTime {
                    let remaining = Int(endTime.timeIntervalSinceNow)
                    if remaining <= 0 {
                        self.isWatchfaceDataCooldownActive = false
                        self.watchfaceSwitchCooldownSeconds = 0
                        self.watchfaceSwitchTimer?.invalidate()
                        self.watchfaceSwitchTimer = nil
                        self.watchfaceSwitchCooldownEndTime = nil
                    } else {
                        self.watchfaceSwitchCooldownSeconds = remaining
                    }
                }
            }
        }

        deinit {
            watchfaceSwitchTimer?.invalidate()
        }
    }
}

extension WatchConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
