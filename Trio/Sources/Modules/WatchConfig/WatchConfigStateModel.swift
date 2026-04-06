import Combine
import ConnectIQ
import SwiftUI

extension WatchConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var garmin: GarminManager!
        @Injected() private var pebble: PebbleManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var devices: [IQDevice] = []
        @Published var confirmBolusFaster = false

        /// Garmin watch settings containing all watch-related configuration
        @Published var garminSettings = GarminWatchSettings()

        // Pebble state
        @Published var pebbleEnabled = false
        @Published var pebbleRunning = false
        @Published var pebblePort: UInt16 = 8080

        var pebbleCommandManager: PebbleCommandManager {
            (pebble as? BasePebbleManager)?.getCommandManager() ?? PebbleCommandManager()
        }

        private(set) var preferences = Preferences()

        override func subscribe() {
            preferences = provider.preferences
            units = settingsManager.settings.units

            // Subscribe to the entire garminSettings struct from TrioSettings
            subscribeSetting(\.garminSettings, on: $garminSettings) { garminSettings = $0 }
            subscribeSetting(\.confirmBolusFaster, on: $confirmBolusFaster) { confirmBolusFaster = $0 }

            devices = garmin.devices

            // Pebble state
            pebbleEnabled = pebble.isEnabled
            pebbleRunning = pebble.isRunning
            if let basePebble = pebble as? BasePebbleManager {
                pebblePort = basePebble.getCurrentPort()
            }

            $pebbleEnabled
                .dropFirst()
                .sink { [weak self] enabled in
                    self?.pebble.isEnabled = enabled
                    self?.pebbleRunning = self?.pebble.isRunning ?? false
                }
                .store(in: &lifetime)
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
        /// to allow the user to switch watchfaces on their Garmin device without data conflicts
        func handleWatchfaceChange() {
            garminSettings.isWatchfaceDataEnabled = false
        }

        /// Resumes data transmission after user confirms they have switched watchface on their device
        func resumeDataTransmission() {
            garminSettings.isWatchfaceDataEnabled = true
        }
    }
}

extension WatchConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
