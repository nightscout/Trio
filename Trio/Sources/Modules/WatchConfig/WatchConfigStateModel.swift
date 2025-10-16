import Combine
import ConnectIQ
import SwiftUI

extension WatchConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var garmin: GarminManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var devices: [IQDevice] = []
        @Published var confirmBolusFaster = false

        /// Current selected Garmin watchface (Trio or SwissAlpine)
        @Published var garminWatchface: GarminWatchface = .trio

        /// Primary data type selection (COB or Sensitivity Ratio)
        @Published var garminDataType1: GarminDataType1 = .cob

        /// Secondary data type selection (TBR or Eventual BG) - SwissAlpine only
        @Published var garminDataType2: GarminDataType2 = .tbr

        /// Controls whether watchface data transmission is disabled
        @Published var garminDisableWatchfaceData: Bool = true

        /// Indicates if the disable toggle is locked during cooldown period
        @Published var isDisableToggleLocked: Bool = false

        /// Remaining seconds in the cooldown period
        @Published var remainingCooldownSeconds: Int = 0

        private(set) var preferences = Preferences()

        /// Timer for managing the 20-second cooldown after watchface changes
        private var cooldownTimer: Timer?

        /// The timestamp when the current cooldown period will end
        private var cooldownEndTime: Date?

        override func subscribe() {
            preferences = provider.preferences
            units = settingsManager.settings.units
            subscribeSetting(\.garminDataType1, on: $garminDataType1) { garminDataType1 = $0 }
            subscribeSetting(\.garminDataType2, on: $garminDataType2) { garminDataType2 = $0 }
            subscribeSetting(\.garminWatchface, on: $garminWatchface) { garminWatchface = $0 }
            subscribeSetting(\.garminDisableWatchfaceData, on: $garminDisableWatchfaceData) { garminDisableWatchfaceData = $0 }
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
            garminDisableWatchfaceData = true
            startCooldownTimer()
        }

        /// Starts a 20-second countdown timer that locks the disable toggle and updates
        /// the remaining seconds display every second until the cooldown period expires
        private func startCooldownTimer() {
            cooldownTimer?.invalidate()

            cooldownEndTime = Date().addingTimeInterval(20)
            isDisableToggleLocked = true
            remainingCooldownSeconds = 20

            cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }

                if let endTime = self.cooldownEndTime {
                    let remaining = Int(endTime.timeIntervalSinceNow)
                    if remaining <= 0 {
                        self.isDisableToggleLocked = false
                        self.remainingCooldownSeconds = 0
                        self.cooldownTimer?.invalidate()
                        self.cooldownTimer = nil
                        self.cooldownEndTime = nil
                    } else {
                        self.remainingCooldownSeconds = remaining
                    }
                }
            }
        }

        deinit {
            cooldownTimer?.invalidate()
        }
    }
}

extension WatchConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
