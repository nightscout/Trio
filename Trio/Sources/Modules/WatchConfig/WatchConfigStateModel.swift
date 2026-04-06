import Combine
import ConnectIQ
import Foundation
import SwiftUI

extension WatchConfig {
    /// Result of the in-app HTTP check against the Pebble local API (`127.0.0.1`).
    struct PebbleConnectionTestResult: Equatable {
        var success: Bool
        var message: String
    }

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
        @Published var lastPebbleConnectionTest: PebbleConnectionTestResult?
        @Published var isPebbleConnectionTestRunning = false

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
                    if enabled == false {
                        self?.lastPebbleConnectionTest = nil
                    }
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

        /// Applies HTTP listen port for the Pebble local API (1024…65535). Persists; restarts server if running.
        func applyPebbleHTTPPort(from raw: String) {
            let digits = raw.filter(\.isNumber)
            guard let value = UInt16(digits), value >= 1024, value <= 65535 else { return }
            (pebble as? BasePebbleManager)?.setPort(value)
            pebblePort = value
            pebbleRunning = pebble.isRunning
            lastPebbleConnectionTest = nil
        }

        /// Fetches `GET /health` and `GET /api/cgm` over loopback to verify the Pebble HTTP server and data path.
        func runPebbleConnectionTest() async {
            let (port, enabled, running) = await MainActor.run { () -> (UInt16, Bool, Bool) in
                isPebbleConnectionTestRunning = true
                lastPebbleConnectionTest = nil
                return (pebblePort, pebbleEnabled, pebbleRunning)
            }

            defer {
                Task { @MainActor in
                    isPebbleConnectionTestRunning = false
                }
            }

            guard enabled else {
                await MainActor.run {
                    lastPebbleConnectionTest = .init(success: false, message: "Turn on Pebble integration first.")
                }
                return
            }
            guard running else {
                await MainActor.run {
                    lastPebbleConnectionTest = .init(
                        success: false,
                        message: "Server is not running. Check the port (no other app may be using it) or toggle Pebble off and on."
                    )
                }
                return
            }

            let base = "http://127.0.0.1:\(port)"
            guard let healthURL = URL(string: base + "/health"),
                  let cgmURL = URL(string: base + "/api/cgm")
            else {
                await MainActor.run {
                    lastPebbleConnectionTest = .init(success: false, message: "Invalid URL for connection test.")
                }
                return
            }

            do {
                let (healthData, healthResp) = try await URLSession.shared.data(from: healthURL)
                guard let healthHttp = healthResp as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard healthHttp.statusCode == 200 else {
                    await MainActor.run {
                        lastPebbleConnectionTest = .init(
                            success: false,
                            message: "/health returned HTTP \(healthHttp.statusCode)."
                        )
                    }
                    return
                }
                let healthSnippet = String(data: healthData, encoding: .utf8) ?? ""

                let (cgmData, cgmResp) = try await URLSession.shared.data(from: cgmURL)
                guard let cgmHttp = cgmResp as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard cgmHttp.statusCode == 200 else {
                    await MainActor.run {
                        lastPebbleConnectionTest = .init(
                            success: false,
                            message: "/health OK (\(healthSnippet)), but /api/cgm returned HTTP \(cgmHttp.statusCode)."
                        )
                    }
                    return
                }

                await MainActor.run {
                    lastPebbleConnectionTest = .init(
                        success: true,
                        message: "Loopback OK. /health: \(healthSnippet) /api/cgm: \(cgmData.count) bytes."
                    )
                }
            } catch {
                await MainActor.run {
                    lastPebbleConnectionTest = .init(
                        success: false,
                        message: error.localizedDescription
                    )
                }
            }
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
