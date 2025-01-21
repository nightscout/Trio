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
        @Published var changeUploadGlucose = true // if plugin, need to be change in CGM configuration
        @Published var useLocalSource = false
        @Published var localPort: Decimal = 0
        @Published var units: GlucoseUnits = .mgdL
        @Published var dia: Decimal = 6
        @Published var maxBasal: Decimal = 2
        @Published var maxBolus: Decimal = 10
        @Published var isConnectedToNS: Bool = false

        @Published var isImportResultReviewPresented: Bool = false
        @Published var importErrors: [String] = []
        @Published var importStatus: ImportStatus = .finished
        @Published var importedInsulinActionCurve: Decimal = 6

        var pumpSettings: PumpSettings {
            provider.getPumpSettings()
        }

        var isPumpSettingUnchanged: Bool {
            pumpSettings.insulinActionCurve == importedInsulinActionCurve
        }

        override func subscribe() {
            url = keychain.getValue(String.self, forKey: Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: Config.secretKey) ?? ""
            units = settingsManager.settings.units
            dia = settingsManager.pumpSettings.insulinActionCurve
            maxBasal = settingsManager.pumpSettings.maxBasal
            maxBolus = settingsManager.pumpSettings.maxBolus
            changeUploadGlucose = (cgmManager.cgmGlucoseSourceType != CGMType.plugin)

            subscribeSetting(\.isUploadEnabled, on: $isUploadEnabled) { isUploadEnabled = $0 }
            subscribeSetting(\.isDownloadEnabled, on: $isDownloadEnabled) { isDownloadEnabled = $0 }
            subscribeSetting(\.useLocalGlucoseSource, on: $useLocalSource) { useLocalSource = $0 }
            subscribeSetting(\.localGlucosePort, on: $localPort.map(Int.init)) { localPort = Decimal($0) }
            subscribeSetting(\.uploadGlucose, on: $uploadGlucose, initial: { uploadGlucose = $0 })

            importedInsulinActionCurve = pumpSettings.insulinActionCurve

            isConnectedToNS = nightscoutAPI != nil

            $isUploadEnabled
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] enabled in
                    guard let self = self else { return }
                    if enabled {
                        debug(.nightscout, "Upload has been enabled by the user.")
                        Task {
                            await self.nightscoutManager.uploadProfiles()
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

        func correctUnitParsingOffsets(_ parsedValue: Decimal) -> Decimal {
            Int(parsedValue) % 2 == 0 ? parsedValue : parsedValue + 1
        }

        func importSettings() async {
            importStatus = .running

            do {
                guard let fetchedProfile = await nightscoutManager.importSettings() else {
                    importStatus = .failed
                    throw NSError(
                        domain: "ImportError",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot find the default Nightscout Profile."]
                    )
                }

                // determine, i.e. guesstimate, whether fetched values are mmol/L or mg/dL values
                let shouldConvertToMgdL = fetchedProfile.units.contains("mmol") || fetchedProfile.target_low
                    .contains(where: { $0.value <= 39 }) || fetchedProfile.target_high.contains(where: { $0.value <= 39 })

                // Carb Ratios
                let carbratios = fetchedProfile.carbratio.map { carbratio in
                    CarbRatioEntry(
                        start: carbratio.time,
                        offset: offset(carbratio.time) / 60,
                        ratio: carbratio.value
                    )
                }

                if carbratios.contains(where: { $0.ratio <= 0 }) {
                    importStatus = .failed
                    throw NSError(
                        domain: "ImportError",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid Carb Ratio settings in Nightscout. Import aborted."]
                    )
                }

                let carbratiosProfile = CarbRatios(units: .grams, schedule: carbratios)

                // Basal Profile
                let pumpName = apsManager.pumpName.value
                let basals = fetchedProfile.basal.map { basal in
                    BasalProfileEntry(
                        start: basal.time,
                        minutes: offset(basal.time) / 60,
                        rate: basal.value
                    )
                }

                if pumpName != "Omnipod DASH", basals.contains(where: { $0.rate <= 0 }) {
                    importStatus = .failed
                    throw NSError(
                        domain: "ImportError",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid Nightscout basal rates found. Import aborted."]
                    )
                }

                if pumpName == "Omnipod DASH", basals.reduce(0, { $0 + $1.rate }) <= 0 {
                    importStatus = .failed
                    throw NSError(
                        domain: "ImportError",
                        code: 4,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Invalid Nightscout basal rates found. Basal rate total cannot be 0 U/hr. Import aborted."
                        ]
                    )
                }

                // Sensitivities
                let sensitivities = fetchedProfile.sens.map { sensitivity in
                    InsulinSensitivityEntry(
                        sensitivity: shouldConvertToMgdL ? correctUnitParsingOffsets(sensitivity.value.asMgdL) : sensitivity
                            .value,
                        offset: offset(sensitivity.time) / 60,
                        start: sensitivity.time
                    )
                }

                if sensitivities.contains(where: { $0.sensitivity <= 0 }) {
                    importStatus = .failed
                    throw NSError(
                        domain: "ImportError",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid Nightscout insulin sensitivity profile. Import aborted."]
                    )
                }

                let sensitivitiesProfile = InsulinSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: sensitivities
                )

                // Targets
                let targets = fetchedProfile.target_low.map { target in
                    BGTargetEntry(
                        low: shouldConvertToMgdL ? correctUnitParsingOffsets(target.value.asMgdL) : target.value,
                        high: shouldConvertToMgdL ? correctUnitParsingOffsets(target.value.asMgdL) : target.value,
                        start: target.time,
                        offset: offset(target.time) / 60
                    )
                }

                let targetsProfile = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: targets)

                // Save to storage and pump
                if let pump = apsManager.pumpManager {
                    let syncValues = basals.map {
                        RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
                    }

                    pump.syncBasalRateSchedule(items: syncValues) { result in
                        switch result {
                        case .success:
                            self.storage.save(basals, as: OpenAPS.Settings.basalProfile)
                            self.finalizeImport(
                                carbratiosProfile: carbratiosProfile,
                                sensitivitiesProfile: sensitivitiesProfile,
                                targetsProfile: targetsProfile,
                                dia: fetchedProfile.dia
                            )
                        case .failure:
                            self.importErrors.append(
                                "Settings were imported but the basal rates could not be saved to pump (communication error)."
                            )
                            self.importStatus = .failed
                        }
                    }

                    if importErrors.isNotEmpty, importStatus == .failed {
                        throw NSError(
                            domain: "ImportError",
                            code: 6,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Settings were imported but the basal rates could not be saved to pump (communication error)."
                            ]
                        )
                    }
                } else {
                    storage.save(basals, as: OpenAPS.Settings.basalProfile)
                    finalizeImport(
                        carbratiosProfile: carbratiosProfile,
                        sensitivitiesProfile: sensitivitiesProfile,
                        targetsProfile: targetsProfile,
                        dia: fetchedProfile.dia
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.importErrors.append(error.localizedDescription)
                    debug(.service, "Settings import failed with error: \(error.localizedDescription)")
                }
            }
        }

        private func finalizeImport(
            carbratiosProfile: CarbRatios,
            sensitivitiesProfile: InsulinSensitivities,
            targetsProfile: BGTargets,
            dia: Decimal
        ) {
            storage.save(carbratiosProfile, as: OpenAPS.Settings.carbRatios)
            storage.save(sensitivitiesProfile, as: OpenAPS.Settings.insulinSensitivities)
            storage.save(targetsProfile, as: OpenAPS.Settings.bgTargets)

            // Save DIA if different
            if dia != self.dia, dia >= 0 {
                let file = PumpSettings(insulinActionCurve: dia, maxBolus: maxBolus, maxBasal: maxBasal)
                storage.save(file, as: OpenAPS.Settings.settings)
                debug(.nightscout, "DIA setting updated to \(dia) after a NS import.")
            }

            debug(.service, "Settings imported successfully.")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // stop blur
                self.importStatus = .finished
                // display next import rewview step
                self.isImportResultReviewPresented = true
            }
        }

        func offset(_ string: String) -> Int {
            let hours = Int(string.prefix(2)) ?? 0
            let minutes = Int(string.suffix(2)) ?? 0
            return ((hours * 60) + minutes) * 60
        }

        func backfillGlucose() async {
            backfilling = true

            let glucose = await nightscoutManager.fetchGlucose(since: Date().addingTimeInterval(-1.days.timeInterval))

            if glucose.isNotEmpty {
                await MainActor.run {
                    self.backfilling = false
                }

                glucoseStorage.storeGlucose(glucose)

                Task.detached {
                    await self.healthKitManager.uploadGlucose()
                }
            } else {
                await MainActor.run {
                    self.backfilling = false
                    debug(.nightscout, "No glucose values found or fetched to backfill.")
                }
            }
        }

        func delete() {
            keychain.removeObject(forKey: Config.urlKey)
            keychain.removeObject(forKey: Config.secretKey)
            url = ""
            secret = ""
            isConnectedToNS = false
        }

        func saveReviewedInsulinAction() {
            if !isPumpSettingUnchanged {
                let settings = PumpSettings(
                    insulinActionCurve: importedInsulinActionCurve,
                    maxBolus: pumpSettings.maxBolus,
                    maxBasal: pumpSettings.maxBasal
                )
                provider.savePumpSettings(settings: settings)
                    .receive(on: DispatchQueue.main)
                    .sink { _ in
                        let settings = self.provider.getPumpSettings()
                        self.importedInsulinActionCurve = settings.insulinActionCurve

                        Task.detached(priority: .low) {
                            debug(.nightscout, "Attempting to upload DIA to Nightscout after import review")
                            await self.nightscoutManager.uploadProfiles()
                        }
                    } receiveValue: {}
                    .store(in: &lifetime)
            }
        }
    }
}

extension NightscoutConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}

extension NightscoutConfig.StateModel {
    enum ImportStatus {
        case running
        case finished
        case failed
        case noPumpConnected
    }
}
