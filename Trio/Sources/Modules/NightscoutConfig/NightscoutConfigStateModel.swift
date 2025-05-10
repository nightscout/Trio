import Combine
import CoreData
import G7SensorKit
import LoopKit
import SwiftDate
import SwiftUI

extension NightscoutConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var keychain: Keychain!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() private var glucoseStorage: GlucoseStorage!
        @Injected() private var healthKitManager: HealthKitManager!
        @Injected() private var cgmManager: FetchGlucoseManager!
        @Injected() private var storage: FileStorage!
        @Injected() var apsManager: APSManager!

        let coredataContext = CoreDataStack.shared.newTaskContext()

        @Published var url = ""
        @Published var secret = ""
        @Published var message = ""
        @Published var isValidURL: Bool = false
        @Published var connecting = false
        @Published var backfilling = false
        @Published var isUploadEnabled = false // Allow uploads
        @Published var isDownloadEnabled = false // Allow downloads
        @Published var uploadGlucose = true // Upload Glucose
        @Published var useLocalSource = false
        @Published var localPort: Decimal = 0
        @Published var units: GlucoseUnits = .mgdL
        @Published var dia: Decimal = 6
        @Published var maxBasal: Decimal = 2
        @Published var maxBolus: Decimal = 10
        @Published var isConnectedToNS: Bool = false

        override func subscribe() {
            url = keychain.getValue(String.self, forKey: Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: Config.secretKey) ?? ""
            units = settingsManager.settings.units
            dia = settingsManager.pumpSettings.insulinActionCurve
            maxBasal = settingsManager.pumpSettings.maxBasal
            maxBolus = settingsManager.pumpSettings.maxBolus

            subscribeSetting(\.isUploadEnabled, on: $isUploadEnabled) { isUploadEnabled = $0 }
            subscribeSetting(\.isDownloadEnabled, on: $isDownloadEnabled) { isDownloadEnabled = $0 }
            subscribeSetting(\.useLocalGlucoseSource, on: $useLocalSource) { useLocalSource = $0 }
            subscribeSetting(\.localGlucosePort, on: $localPort.map(Int.init)) { localPort = Decimal($0) }
            subscribeSetting(\.uploadGlucose, on: $uploadGlucose, initial: { uploadGlucose = $0 })

            isConnectedToNS = nightscoutAPI != nil

            $isUploadEnabled
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] enabled in
                    guard let self = self else { return }
                    if enabled {
                        debug(.nightscout, "Upload has been enabled by the user.")
                        Task {
                            do {
                                try await self.nightscoutManager.uploadProfiles()
                            } catch {
                                debug(
                                    .default,
                                    "\(DebuggingIdentifiers.failed) failed to upload profiles: \(error)"
                                )
                            }
                        }
                    } else {
                        debug(.nightscout, "Upload has been disabled by the user.")
                    }
                }
                .store(in: &lifetime)
        }

        func connect() {
            if let CheckURL = url.last, CheckURL == "/" {
                let fixedURL = url.dropLast()
                url = String(fixedURL)
            }

            guard let url = URL(string: url), self.url.hasPrefix("https://") else {
                message = "Invalid URL"
                isValidURL = false
                return
            }

            connecting = true
            isValidURL = true
            message = ""

            provider.checkConnection(url: url, secret: secret.isEmpty ? nil : secret)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished: break
                    case let .failure(error):
                        self.message = "Error: \(error.localizedDescription)"
                    }
                    self.connecting = false
                } receiveValue: {
                    self.message = "Connected!"
                    self.keychain.setValue(self.url, forKey: Config.urlKey)
                    self.keychain.setValue(self.secret, forKey: Config.secretKey)
                    self.connecting = true
                    self.isConnectedToNS = self.nightscoutAPI != nil
                }
                .store(in: &lifetime)
        }

        private var nightscoutAPI: NightscoutAPI? {
            guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
                  let url = URL(string: urlString),
                  let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
            else {
                return nil
            }
            return NightscoutAPI(url: url, secret: secret)
        }

        private func getMedianTarget(
            lowTargetValue: Decimal,
            lowTargetTime: String,
            highTarget: [NightscoutTimevalue],
            units: GlucoseUnits
        ) -> Decimal {
            if let idx = highTarget.firstIndex(where: { $0.time == lowTargetTime }) {
                let median = (lowTargetValue + highTarget[idx].value) / 2
                switch units {
                case .mgdL:
                    return Decimal(round(Double(median)))
                case .mmolL:
                    return Decimal(round(Double(median) * 10) / 10)
                }
            }
            return lowTargetValue
        }

        func backfillGlucose() async {
            await MainActor.run {
                backfilling = true
            }

            let glucose = await nightscoutManager.fetchGlucose(since: Date().addingTimeInterval(-1.days.timeInterval))

            if glucose.isNotEmpty {
                do {
                    try await glucoseStorage.storeGlucose(glucose)

                    Task.detached {
                        await self.healthKitManager.uploadGlucose()
                    }
                } catch let error as CoreDataError {
                    debug(.nightscout, "Core Data error while storing backfilled glucose: \(error)")
                    message = "Error: \(error.localizedDescription)"
                } catch {
                    debug(.nightscout, "Unexpected error while storing backfilled glucose: \(error)")
                    message = "Error: \(error.localizedDescription)"
                }
            } else {
                debug(.nightscout, "No glucose values found or fetched to backfill.")
            }

            await MainActor.run {
                self.backfilling = false
            }
        }

        func delete() {
            keychain.removeObject(forKey: Config.urlKey)
            keychain.removeObject(forKey: Config.secretKey)
            url = ""
            secret = ""
            isConnectedToNS = false
        }
    }
}

extension NightscoutConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
