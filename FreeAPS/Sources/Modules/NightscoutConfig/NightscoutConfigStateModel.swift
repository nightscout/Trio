import CGMBLEKit
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

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        @Published var url = ""
        @Published var secret = ""
        @Published var message = ""
        @Published var connecting = false
        @Published var backfilling = false
        @Published var isUploadEnabled = false // Allow uploads
        @Published var uploadStats = false // Upload Statistics
        @Published var uploadGlucose = true // Upload Glucose
        @Published var useLocalSource = false
        @Published var localPort: Decimal = 0
        @Published var units: GlucoseUnits = .mmolL
        @Published var dia: Decimal = 6
        @Published var maxBasal: Decimal = 2
        @Published var maxBolus: Decimal = 10
        @Published var allowAnnouncements: Bool = false

        override func subscribe() {
            url = keychain.getValue(String.self, forKey: Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: Config.secretKey) ?? ""
            units = settingsManager.settings.units
            dia = settingsManager.pumpSettings.insulinActionCurve
            maxBasal = settingsManager.pumpSettings.maxBasal
            maxBolus = settingsManager.pumpSettings.maxBolus

            subscribeSetting(\.allowAnnouncements, on: $allowAnnouncements) { allowAnnouncements = $0 }
            subscribeSetting(\.isUploadEnabled, on: $isUploadEnabled) { isUploadEnabled = $0 }
            subscribeSetting(\.useLocalGlucoseSource, on: $useLocalSource) { useLocalSource = $0 }
            subscribeSetting(\.localGlucosePort, on: $localPort.map(Int.init)) { localPort = Decimal($0) }
            subscribeSetting(\.uploadStats, on: $uploadStats) { uploadStats = $0 }
            subscribeSetting(\.uploadGlucose, on: $uploadGlucose, initial: { uploadGlucose = $0 }, didSet: { val in
                if let cgmManagerG5 = self.cgmManager.glucoseSource.cgmManager as? G5CGMManager {
                    cgmManagerG5.shouldSyncToRemoteService = val
                }
                if let cgmManagerG6 = self.cgmManager.glucoseSource.cgmManager as? G6CGMManager {
                    cgmManagerG6.shouldSyncToRemoteService = val
                }
                if let cgmManagerG7 = self.cgmManager.glucoseSource.cgmManager as? G7CGMManager {
                    cgmManagerG7.uploadReadings = val
                }
            })
        }

        func connect() {
            if let CheckURL = url.last, CheckURL == "/" {
                let fixedURL = url.dropLast()
                url = String(fixedURL)
            }
            guard let url = URL(string: url) else {
                message = "Invalid URL"
                return
            }
            connecting = true
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

        func importSettings() {
            guard let nightscout = nightscoutAPI else {
                saveError("Can't access nightscoutAPI")
                return
            }
            let group = DispatchGroup()
            group.enter()
            var error = ""
            let path = "/api/v1/profile.json"
            let timeout: TimeInterval = 60

            var components = URLComponents()
            components.scheme = nightscout.url.scheme
            components.host = nightscout.url.host
            components.port = nightscout.url.port
            components.path = path
            components.queryItems = [
                URLQueryItem(name: "count", value: "1")
            ]
            var url = URLRequest(url: components.url!)
            url.allowsConstrainedNetworkAccess = false
            url.timeoutInterval = timeout

            if let secret = nightscout.secret {
                url.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
            }
            let task = URLSession.shared.dataTask(with: url) { data, response, error_ in
                if let error_ = error_ {
                    print("Error occured: " + error_.localizedDescription)
                    // handle error
                    self.saveError("Error occured: " + error_.localizedDescription)
                    error = error_.localizedDescription
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ... 299).contains(httpResponse.statusCode)
                else {
                    print("Error occured! " + error_.debugDescription)
                    // handle error
                    self.saveError(error_.debugDescription)
                    return
                }
                let jsonDecoder = JSONCoding.decoder

                if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                   let data = data
                {
                    do {
                        let fetchedProfileStore = try jsonDecoder.decode([FetchedNightscoutProfileStore].self, from: data)
                        guard let fetchedProfile: ScheduledNightscoutProfile = fetchedProfileStore.first?.store["default"]
                        else {
                            error = "\nCan't find the default Nightscout Profile."
                            group.leave()
                            return
                        }

                        guard fetchedProfile.units.contains(self.units.rawValue.prefix(4)) else {
                            debug(
                                .nightscout,
                                "Mismatching glucose units in Nightscout and Pump Settings. Import settings aborted."
                            )
                            error = "\nMismatching glucose units in Nightscout and Pump Settings. Import settings aborted."
                            group.leave()
                            return
                        }

                        var areCRsOK = true
                        let carbratios = fetchedProfile.carbratio
                            .map { carbratio -> CarbRatioEntry in
                                if carbratio.value <= 0 {
                                    error =
                                        "\nInvalid Carb Ratio settings in Nightscout.\n\nImport aborted. Please check your Nightscout Profile Carb Ratios Settings!"
                                    areCRsOK = false
                                }
                                return CarbRatioEntry(
                                    start: carbratio.time,
                                    offset: self.offset(carbratio.time) / 60,
                                    ratio: carbratio.value
                                ) }
                        let carbratiosProfile = CarbRatios(units: CarbUnit.grams, schedule: carbratios)
                        guard areCRsOK else {
                            group.leave()
                            return
                        }

                        var areBasalsOK = true
                        let pumpName = self.apsManager.pumpName.value
                        let basals = fetchedProfile.basal
                            .map { basal -> BasalProfileEntry in
                                if pumpName != "Omnipod DASH", basal.value <= 0
                                {
                                    error =
                                        "\nInvalid Nightcsout Basal Settings. Some or all of your basal settings are 0 U/h.\n\nImport aborted. Please check your Nightscout Profile Basal Settings before trying to import again. Import has been aborted.)"
                                    areBasalsOK = false
                                }
                                return BasalProfileEntry(
                                    start: basal.time,
                                    minutes: self.offset(basal.time) / 60,
                                    rate: basal.value
                                ) }
                        // DASH pumps can have 0U/h basal rates but don't import if total basals (24 hours) amount to 0 U.
                        if pumpName == "Omnipod DASH", basals.map({ each in each.rate }).reduce(0, +) <= 0
                        {
                            error =
                                "\nYour total Basal insulin amount to 0 U or lower in Nightscout Profile settings.\n\n Please check your Nightscout Profile Basal Settings before trying to import again. Import has been aborted.)"
                            areBasalsOK = false
                        }
                        guard areBasalsOK else {
                            group.leave()
                            return
                        }

                        let sensitivities = fetchedProfile.sens.map { sensitivity -> InsulinSensitivityEntry in
                            InsulinSensitivityEntry(
                                sensitivity: self.units == .mmolL ? sensitivity.value : sensitivity.value.asMgdL,
                                offset: self.offset(sensitivity.time) / 60,
                                start: sensitivity.time
                            )
                        }
                        if sensitivities.filter({ $0.sensitivity <= 0 }).isNotEmpty {
                            error =
                                "\nInvalid Nightcsout Sensitivities Settings. \n\nImport aborted. Please check your Nightscout Profile Sensitivities Settings!"
                            group.leave()
                            return
                        }

                        let sensitivitiesProfile = InsulinSensitivities(
                            units: self.units,
                            userPrefferedUnits: self.units,
                            sensitivities: sensitivities
                        )

                        let targets = fetchedProfile.target_low
                            .map { target -> BGTargetEntry in
                                BGTargetEntry(
                                    low: self.units == .mmolL ? target.value : target.value.asMgdL,
                                    high: self.units == .mmolL ? target.value : target.value.asMgdL,
                                    start: target.time,
                                    offset: self.offset(target.time) / 60
                                ) }
                        let targetsProfile = BGTargets(
                            units: self.units,
                            userPrefferedUnits: self.units,
                            targets: targets
                        )
                        // IS THERE A PUMP?
                        guard let pump = self.apsManager.pumpManager else {
                            self.storage.save(carbratiosProfile, as: OpenAPS.Settings.carbRatios)
                            self.storage.save(basals, as: OpenAPS.Settings.basalProfile)
                            self.storage.save(sensitivitiesProfile, as: OpenAPS.Settings.insulinSensitivities)
                            self.storage.save(targetsProfile, as: OpenAPS.Settings.bgTargets)
                            debug(
                                .service,
                                "Settings were imported but the Basals couldn't be saved to pump (No pump). Check your basal settings and tap ´Save on Pump´ to sync the new basal settings"
                            )
                            error =
                                "\nSettings were imported but the Basals couldn't be saved to pump (No pump). Check your basal settings and tap ´Save on Pump´ to sync the new basal settings"
                            group.leave()
                            return
                        }
                        let syncValues = basals.map {
                            RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
                        }
                        // SSAVE TO STORAGE. SAVE TO PUMP (LoopKit)
                        pump.syncBasalRateSchedule(items: syncValues) { result in
                            switch result {
                            case .success:
                                self.storage.save(basals, as: OpenAPS.Settings.basalProfile)
                                self.storage.save(carbratiosProfile, as: OpenAPS.Settings.carbRatios)
                                self.storage.save(sensitivitiesProfile, as: OpenAPS.Settings.insulinSensitivities)
                                self.storage.save(targetsProfile, as: OpenAPS.Settings.bgTargets)
                                debug(.service, "Settings have been imported and the Basals saved to pump!")
                                // DIA. Save if changed.
                                let dia = fetchedProfile.dia
                                print("dia: " + dia.description)
                                print("pump dia: " + self.dia.description)
                                if dia != self.dia, dia >= 0 {
                                    let file = PumpSettings(
                                        insulinActionCurve: dia,
                                        maxBolus: self.maxBolus,
                                        maxBasal: self.maxBasal
                                    )
                                    self.storage.save(file, as: OpenAPS.Settings.settings)
                                    debug(.nightscout, "DIA setting updated to " + dia.description + " after a NS import.")
                                }
                                group.leave()
                            case .failure:
                                error =
                                    "\nSettings were imported but the Basals couldn't be saved to pump (communication error). Check your basal settings and tap ´Save on Pump´ to sync the new basal settings"
                                debug(.service, "Basals couldn't be save to pump")
                                group.leave()
                            }
                        }
                    } catch let parsingError {
                        print(parsingError)
                        error = parsingError.localizedDescription
                        group.leave()
                    }
                }
            }
            task.resume()
            group.wait(wallTimeout: .now() + 5)
            group.notify(queue: .global(qos: .background)) {
                self.saveError(error)
            }
        }

        func offset(_ string: String) -> Int {
            let hours = Int(string.prefix(2)) ?? 0
            let minutes = Int(string.suffix(2)) ?? 0
            return ((hours * 60) + minutes) * 60
        }

        func saveError(_ string: String) {
            coredataContext.performAndWait {
                let saveToCoreData = ImportError(context: self.coredataContext)
                saveToCoreData.date = Date()
                saveToCoreData.error = string
                if coredataContext.hasChanges {
                    try? coredataContext.save()
                }
            }
        }

        func backfillGlucose() {
            backfilling = true
            nightscoutManager.fetchGlucose(since: Date().addingTimeInterval(-1.days.timeInterval))
                .sink { [weak self] glucose in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.backfilling = false
                    }

                    guard glucose.isNotEmpty else { return }
                    self.healthKitManager.saveIfNeeded(bloodGlucose: glucose)
                    self.glucoseStorage.storeGlucose(glucose)
                }
                .store(in: &lifetime)
        }

        func delete() {
            keychain.removeObject(forKey: Config.urlKey)
            keychain.removeObject(forKey: Config.secretKey)
            url = ""
            secret = ""
        }
    }
}
