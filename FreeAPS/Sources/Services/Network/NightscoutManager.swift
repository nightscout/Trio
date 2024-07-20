import Combine
import CoreData
import Foundation
import LoopKitUI
import Swinject
import UIKit

protocol NightscoutManager: GlucoseSource {
    func fetchGlucose(since date: Date) async -> [BloodGlucose]
    func fetchCarbs() async -> [CarbsEntry]
    func fetchTempTargets() async -> [TempTarget]
    func fetchAnnouncements() -> AnyPublisher<[Announcement], Never>
    func deleteCarbs(withID id: String) async
    func deleteInsulin(withID id: String) async
    func deleteManualGlucose(withID id: String) async
    func uploadStatus() async
    func uploadGlucose() async
    func uploadManualGlucose() async
    func uploadStatistics(dailystat: Statistics) async
    func uploadPreferences(_ preferences: Preferences)
    func uploadProfileAndSettings(_: Bool)
    var cgmURL: URL? { get }
}

final class BaseNightscoutManager: NightscoutManager, Injectable {
    @Injected() private var keychain: Keychain!
    @Injected() private var determinationStorage: DeterminationStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var overridesStorage: OverrideStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var reachabilityManager: ReachabilityManager!
    @Injected() var healthkitManager: HealthKitManager!

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")
    private var ping: TimeInterval?

    private var backgroundContext = CoreDataStack.shared.newTaskContext()

    private var lifetime = Lifetime()

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private var isUploadEnabled: Bool {
        settingsManager.settings.isUploadEnabled
    }

    private var isUploadGlucoseEnabled: Bool {
        settingsManager.settings.uploadGlucose
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

    private var lastEnactedDetermination: Determination?
    private var lastSuggestedDetermination: Determination?

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        setupNotification()
        _ = reachabilityManager.startListening(onQueue: processQueue) { status in
            debug(.nightscout, "Network status: \(status)")
        }
    }

    func sourceInfo() -> [String: Any]? {
        if let ping = ping {
            return [GlucoseSourceKey.nightscoutPing.rawValue: ping]
        }
        return nil
    }

    var cgmURL: URL? {
        if let url = settingsManager.settings.cgm.appURL {
            return url
        }

        let useLocal = settingsManager.settings.useLocalGlucoseSource

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        return maybeNightscout?.url
    }

    func fetchGlucose(since date: Date) async -> [BloodGlucose] {
        let useLocal = settingsManager.settings.useLocalGlucoseSource
        ping = nil

        if !useLocal {
            guard isNetworkReachable else {
                return []
            }
        }

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        guard let nightscout = maybeNightscout else {
            return []
        }

        let startDate = Date()

        do {
            let glucose = try await nightscout.fetchLastGlucose(sinceDate: date)
            if glucose.isNotEmpty {
                ping = Date().timeIntervalSince(startDate)
            }
            return glucose
        } catch {
            print(error.localizedDescription)
            return []
        }
    }

    // MARK: - GlucoseSource

    var glucoseManager: FetchGlucoseManager?
    var cgmManager: CGMManagerUI?
    var cgmType: CGMType = .nightscout

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Future { promise in
            Task {
                let glucoseData = await self.fetchGlucose(since: self.glucoseStorage.syncDate())
                promise(.success(glucoseData))
            }
        }
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }

    func fetchCarbs() async -> [CarbsEntry] {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return []
        }

        let since = carbsStorage.syncDate()
        do {
            let carbs = try await nightscout.fetchCarbs(sinceDate: since)
            return carbs
        } catch {
            debug(.nightscout, "Error fetching carbs: \(error.localizedDescription)")
            return []
        }
    }

    func fetchTempTargets() async -> [TempTarget] {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return []
        }

        let since = tempTargetsStorage.syncDate()
        do {
            let tempTargets = try await nightscout.fetchTempTargets(sinceDate: since)
            return tempTargets
        } catch {
            debug(.nightscout, "Error fetching temp targets: \(error.localizedDescription)")
            return []
        }
    }

    func fetchAnnouncements() -> AnyPublisher<[Announcement], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }

        let since = announcementsStorage.syncDate()
        return nightscout.fetchAnnouncement(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func deleteCarbs(withID id: String) async {
        guard let nightscout = nightscoutAPI, isUploadEnabled else { return }

        // TODO: - healthkit rewrite, deletion of FPUs
//        healthkitManager.deleteCarbs(syncID: arg1, fpuID: arg2)

        do {
            try await nightscout.deleteCarbs(withId: id)
            debug(.nightscout, "Carbs deleted")
        } catch {
            debug(
                .nightscout,
                "\(DebuggingIdentifiers.failed) Failed to delete Carbs from Nightscout with error: \(error.localizedDescription)"
            )
        }
    }

    func deleteInsulin(withID id: String) async {
        guard let nightscout = nightscoutAPI, isUploadEnabled else { return }

        do {
            try await nightscout.deleteInsulin(withId: id)
            debug(.nightscout, "Insulin deleted")
        } catch {
            debug(
                .nightscout,
                "\(DebuggingIdentifiers.failed) Failed to delete Insulin from Nightscout with error: \(error.localizedDescription)"
            )
        }
    }

    func deleteManualGlucose(withID id: String) async {
        guard let nightscout = nightscoutAPI, isUploadEnabled else { return }

        do {
            try await nightscout.deleteManualGlucose(withId: id)
        } catch {
            debug(
                .nightscout,
                "\(DebuggingIdentifiers.failed) Failed to delete Manual Glucose from Nightscout with error: \(error.localizedDescription)"
            )
        }
    }

    func uploadStatistics(dailystat: Statistics) async {
        let stats = NightscoutStatistics(dailystats: dailystat)

        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            try await nightscout.uploadStats(stats)
            debug(.nightscout, "Statistics uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    func uploadPreferences(_ preferences: Preferences) {
        let prefs = NightscoutPreferences(
            preferences: settingsManager.preferences
        )

        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            nightscout.uploadPrefs(prefs)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Preferences uploaded")
                        self.storage.save(preferences, as: OpenAPS.Nightscout.uploadedPreferences)
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func uploadSettings(_ settings: FreeAPSSettings) {
        let sets = NightscoutSettings(
            settings: settingsManager.settings
        )

        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            nightscout.uploadSettings(sets)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Settings uploaded")
                        self.storage.save(settings, as: OpenAPS.Nightscout.uploadedSettings)
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    private func fetchBattery() -> Battery {
        backgroundContext.performAndWait {
            do {
                let results = try backgroundContext.fetch(OpenAPS_Battery.fetch(NSPredicate.predicateFor30MinAgo))
                if let last = results.first {
                    let percent: Int? = Int(last.percent)
                    let voltage: Decimal? = last.voltage as Decimal?
                    let status: String? = last.status
                    let display: Bool? = last.display

                    if let percent = percent, let voltage = voltage, let status = status, let display = display {
                        debugPrint(
                            "Home State Model: \(#function) \(DebuggingIdentifiers.succeeded) setup battery from core data successfully"
                        )
                        return Battery(
                            percent: percent,
                            voltage: voltage,
                            string: BatteryState(rawValue: status) ?? BatteryState.normal,
                            display: display
                        )
                    }
                }
                return Battery(percent: 100, voltage: 100, string: BatteryState.normal, display: false)
            } catch {
                debugPrint(
                    "Home State Model: \(#function) \(DebuggingIdentifiers.failed) failed to setup battery from core data"
                )
                return Battery(percent: 100, voltage: 100, string: BatteryState.normal, display: false)
            }
        }
    }

    func uploadStatus() async {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            debug(.nightscout, "NS API not available or upload disabled. Aborting NS Status upload.")
            return
        }

        let fetchedEnactedDetermination = await determinationStorage.getOrefDeterminationNotYetUploadedToNightscout(
            await determinationStorage
                .fetchLastDeterminationObjectID(predicate: NSPredicate.enactedDeterminationsNotYetUploadedToNightscout)
        )

        let fetchedSuggestedDetermination = await determinationStorage.getOrefDeterminationNotYetUploadedToNightscout(
            await determinationStorage
                .fetchLastDeterminationObjectID(predicate: NSPredicate.suggestedDeterminationsNotYetUploadedToNightscout)
        )

        //         TODO: this seems to block to many things… when just adding meal or a bolus, we don't always see upload. race condition?
        //         Guard to ensure both determinations are not nil
        guard fetchedEnactedDetermination != nil || fetchedSuggestedDetermination != nil else {
            debug(
                .nightscout,
                "Both fetchedEnactedDetermination and fetchedSuggestedDetermination are nil. Aborting NS Status upload."
            )
            return
        }
        // Unwrap fetchedSuggestedDetermination and manipulate the timestamp field to ensure deliverAt and timestamp for a suggestion truly match!
        var modifiedSuggestedDetermination = fetchedSuggestedDetermination
        if var suggestion = fetchedSuggestedDetermination {
            suggestion.timestamp = suggestion.deliverAt
            modifiedSuggestedDetermination = suggestion
        }

        // Check whether the last suggestion that was uploaded is the same that is fetched again when we are attempting to upload the enacted determination
        // Apparently we are too fast; so the flag update is not fast enough to have the predicate filter last suggestion out
        // If this check is truthy, set suggestion to nil so it's not uploaded again
        if let lastSuggested = lastSuggestedDetermination, let suggestion = modifiedSuggestedDetermination,
           lastSuggested.deliverAt == suggestion.deliverAt 
        {
            modifiedSuggestedDetermination = nil
        }

        // Gather all relevant data for OpenAPS Status
        let iob = storage.retrieve(OpenAPS.Monitor.iob, as: [IOBEntry].self)
        let openapsStatus = OpenAPSStatus(
            iob: iob?.first,
            suggested: modifiedSuggestedDetermination,
            enacted: settingsManager.settings.closedLoop ? fetchedEnactedDetermination : nil,
            version: "0.7.1"
        )

        // Gather all relevant data for NS Status
        let battery = fetchBattery()
        let reservoir = Decimal(from: storage.retrieveRaw(OpenAPS.Monitor.reservoir) ?? "0")
        let pumpStatus = storage.retrieve(OpenAPS.Monitor.status, as: PumpStatus.self)
        let pump = NSPumpStatus(
            clock: Date(),
            battery: battery,
            reservoir: reservoir != 0xDEAD_BEEF ? reservoir : nil,
            status: pumpStatus
        )
        let device = await UIDevice.current
        let uploader = await Uploader(batteryVoltage: nil, battery: Int(device.batteryLevel * 100))
        let status = NightscoutStatus(
            device: NightscoutTreatment.local,
            openaps: openapsStatus,
            pump: pump,
            uploader: uploader
        )

//        if let lastSuggested = lastSuggestedDetermination, let fetchedEnacted = fetchedEnactedDetermination,
//           lastSuggested.deliverAt == fetchedEnacted.deliverAt
//        {
//            debug(
//                .nightscout,
//                "Matching deliverAt detected and less than 1 second since lastSuggested, delaying upload by 3 seconds"
//            )
//            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000) // 3 seconds delay
//        }

        do {
            try await nightscout.uploadStatus(status)
            debug(.nightscout, "Status uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }

        if let enacted = fetchedEnactedDetermination {
            await updateOrefDeterminationAsUploaded([enacted])
        }

        if let suggested = fetchedSuggestedDetermination {
            await updateOrefDeterminationAsUploaded([suggested])
        }

        debug(.nightscout, "NSDeviceStatus with Determination uploaded")

        Task.detached {
            await self.uploadPodAge()
        }

        lastEnactedDetermination = fetchedEnactedDetermination
        lastSuggestedDetermination = fetchedSuggestedDetermination
    }

    private func updateOrefDeterminationAsUploaded(_ determination: [Determination]) async {
        await backgroundContext.perform {
            let ids = determination.map(\.id) as NSArray
            print("\(DebuggingIdentifiers.inProgress) ids: \(ids)")
            let fetchRequest: NSFetchRequest<OrefDetermination> = OrefDetermination.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                print("\(DebuggingIdentifiers.inProgress) results: \(results)")
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    func uploadPodAge() async {
        let uploadedPodAge = storage.retrieve(OpenAPS.Nightscout.uploadedPodAge, as: [NightscoutTreatment].self) ?? []
        if let podAge = storage.retrieve(OpenAPS.Monitor.podAge, as: Date.self),
           uploadedPodAge.last?.createdAt == nil || podAge != uploadedPodAge.last!.createdAt!
        {
            let siteTreatment = NightscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsSiteChange,
                createdAt: podAge,
                enteredBy: NightscoutTreatment.local,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
            await uploadTreatments([siteTreatment], fileToSave: OpenAPS.Nightscout.uploadedPodAge)
        }
    }

    func uploadProfileAndSettings(_ force: Bool) {
        guard let sensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading insulinSensitivities")
            return
        }
        guard let settings = storage.retrieve(OpenAPS.FreeAPS.settings, as: FreeAPSSettings.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading settings")
            return
        }
        guard let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading preferences")
            return
        }
        guard let targets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading bgTargets")
            return
        }
        guard let carbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading carbRatios")
            return
        }
        guard let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading basalProfile")
            return
        }

        let sens = sensitivities.sensitivities.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.sensitivity,
                timeAsSeconds: item.offset * 60
            )
        }
        let target_low = targets.targets.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.low,
                timeAsSeconds: item.offset * 60
            )
        }
        let target_high = targets.targets.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.high,
                timeAsSeconds: item.offset * 60
            )
        }
        let cr = carbRatios.schedule.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.ratio,
                timeAsSeconds: item.offset * 60
            )
        }
        let basal = basalProfile.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.rate,
                timeAsSeconds: item.minutes * 60
            )
        }

        var nsUnits = ""
        switch settingsManager.settings.units {
        case .mgdL:
            nsUnits = "mg/dl"
        case .mmolL:
            nsUnits = "mmol"
        }

        var carbs_hr: Decimal = 0
        if let isf = sensitivities.sensitivities.map(\.sensitivity).first,
           let cr = carbRatios.schedule.map(\.ratio).first,
           isf > 0, cr > 0
        {
            // CarbImpact -> Carbs/hr = CI [mg/dl/5min] * 12 / ISF [mg/dl/U] * CR [g/U]
            carbs_hr = settingsManager.preferences.min5mCarbimpact * 12 / isf * cr
            if settingsManager.settings.units == .mmolL {
                carbs_hr = carbs_hr * GlucoseUnits.exchangeRate
            }
            // No, Decimal has no rounding function.
            carbs_hr = Decimal(round(Double(carbs_hr) * 10.0)) / 10
        }

        let ps = ScheduledNightscoutProfile(
            dia: settingsManager.pumpSettings.insulinActionCurve,
            carbs_hr: Int(carbs_hr),
            delay: 0,
            timezone: TimeZone.current.identifier,
            target_low: target_low,
            target_high: target_high,
            sens: sens,
            basal: basal,
            carbratio: cr,
            units: nsUnits
        )
        let defaultProfile = "default"

        let now = Date()
        let p = NightscoutProfileStore(
            defaultProfile: defaultProfile,
            startDate: now,
            mills: Int(now.timeIntervalSince1970) * 1000,
            units: nsUnits,
            enteredBy: NightscoutTreatment.local,
            store: [defaultProfile: ps]
        )

        guard let nightscout = nightscoutAPI, isNetworkReachable, isUploadEnabled else {
            return
        }

        // UPLOAD PREFERNCES WHEN CHANGED
        if let uploadedPreferences = storage.retrieve(OpenAPS.Nightscout.uploadedPreferences, as: Preferences.self),
           uploadedPreferences.rawJSON.sorted() == preferences.rawJSON.sorted(), !force
        {
            NSLog("NightscoutManager Preferences, preferences unchanged")
        } else { uploadPreferences(preferences) }

        // UPLOAD FreeAPS Settings WHEN CHANGED
        if let uploadedSettings = storage.retrieve(OpenAPS.Nightscout.uploadedSettings, as: FreeAPSSettings.self),
           uploadedSettings.rawJSON.sorted() == settings.rawJSON.sorted(), !force
        {
            NSLog("NightscoutManager Settings, settings unchanged")
        } else { uploadSettings(settings) }

        // UPLOAD Profiles WHEN CHANGED
        if let uploadedProfile = storage.retrieve(OpenAPS.Nightscout.uploadedProfile, as: NightscoutProfileStore.self),
           (uploadedProfile.store["default"]?.rawJSON ?? "").sorted() == ps.rawJSON.sorted(), !force
        {
            NSLog("NightscoutManager uploadProfile, no profile change")
        } else {
            processQueue.async {
                nightscout.uploadProfile(p)
                    .sink { completion in
                        switch completion {
                        case .finished:
                            self.storage.save(p, as: OpenAPS.Nightscout.uploadedProfile)
                            debug(.nightscout, "Profile uploaded")
                        case let .failure(error):
                            debug(.nightscout, error.localizedDescription)
                        }
                    } receiveValue: {}
                    .store(in: &self.lifetime)
            }
        }
    }

    func uploadGlucose() async {
        await uploadGlucose(glucoseStorage.getGlucoseNotYetUploadedToNightscout())
        await uploadTreatments(
            glucoseStorage.getCGMStateNotYetUploadedToNightscout(),
            fileToSave: OpenAPS.Nightscout.uploadedCGMState
        )
    }

    func uploadManualGlucose() async {
        await uploadManualGlucose(glucoseStorage.getManualGlucoseNotYetUploadedToNightscout())
    }

    private func uploadPumpHistory() async {
        await uploadTreatments(
            pumpHistoryStorage.getPumpHistoryNotYetUploadedToNightscout(),
            fileToSave: OpenAPS.Nightscout.uploadedPumphistory
        )
    }

    private func uploadCarbs() async {
        await uploadCarbs(carbsStorage.getCarbsNotYetUploadedToNightscout())
        await uploadCarbs(carbsStorage.getFPUsNotYetUploadedToNightscout())
    }

    private func uploadOverrides() async {
        await uploadOverrides(overridesStorage.getOverridesNotYetUploadedToNightscout())
        await uploadOverrideRuns(overridesStorage.getOverrideRunsNotYetUploadedToNightscout())
    }

    private func uploadTempTargets() async {
        await uploadTreatments(
            tempTargetsStorage.nightscoutTreatmentsNotUploaded(),
            fileToSave: OpenAPS.Nightscout.uploadedTempTargets
        )
    }

    private func uploadGlucose(_ glucose: [BloodGlucose]) async {
        guard !glucose.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled, isUploadGlucoseEnabled else {
            return
        }

        do {
            // Upload in Batches of 100
            for chunk in glucose.chunks(ofCount: 100) {
                try await nightscout.uploadGlucose(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the GlucoseStored objects
            await updateGlucoseAsUploaded(glucose)

            debug(.nightscout, "Glucose uploaded")
        } catch {
            debug(.nightscout, "Upload of glucose failed: \(error.localizedDescription)")
        }
    }

    private func updateGlucoseAsUploaded(_ glucose: [BloodGlucose]) async {
        await backgroundContext.perform {
            let ids = glucose.map(\.id) as NSArray
            print("\(DebuggingIdentifiers.inProgress) ids: \(ids)")
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                print("\(DebuggingIdentifiers.inProgress) results: \(results)")
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadTreatments(_ treatments: [NightscoutTreatment], fileToSave _: String) async {
        guard !treatments.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in treatments.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the PumpEventStored objects
            await updateTreatmentsAsUploaded(treatments)

            debug(.nightscout, "Treatments uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func updateTreatmentsAsUploaded(_ treatments: [NightscoutTreatment]) async {
        await backgroundContext.perform {
            let ids = treatments.map(\.id) as NSArray
            print("\(DebuggingIdentifiers.inProgress) ids: \(ids)")
            let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                print("\(DebuggingIdentifiers.inProgress) results: \(results)")
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadManualGlucose(_ treatments: [NightscoutTreatment]) async {
        guard !treatments.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in treatments.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the GlucoseStored objects
            await updateManualGlucoseAsUploaded(treatments)

            debug(.nightscout, "Treatments uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func updateManualGlucoseAsUploaded(_ treatments: [NightscoutTreatment]) async {
        await backgroundContext.perform {
            let ids = treatments.map(\.id) as NSArray
            print("\(DebuggingIdentifiers.inProgress) ids: \(ids)")
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                print("\(DebuggingIdentifiers.inProgress) results: \(results)")
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadCarbs(_ treatments: [NightscoutTreatment]) async {
        guard !treatments.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in treatments.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the CarbEntryStored objects
            await updateCarbsAsUploaded(treatments)

            debug(.nightscout, "Treatments uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func updateCarbsAsUploaded(_ treatments: [NightscoutTreatment]) async {
        await backgroundContext.perform {
            let ids = treatments.map(\.id) as NSArray
            print("\(DebuggingIdentifiers.inProgress) ids: \(ids)")
            let fetchRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                print("\(DebuggingIdentifiers.inProgress) results: \(results)")
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadOverrides(_ overrides: [NightscoutExercise]) async {
        guard !overrides.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in overrides.chunks(ofCount: 100) {
                try await nightscout.uploadOverrides(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the OverrideStored objects
            await updateOverridesAsUploaded(overrides)

            debug(.nightscout, "Overrides uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func updateOverridesAsUploaded(_ overrides: [NightscoutExercise]) async {
        await backgroundContext.perform {
            let ids = overrides.map(\.id) as NSArray
            print("\(DebuggingIdentifiers.inProgress) ids: \(ids)")
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                print("\(DebuggingIdentifiers.inProgress) results: \(results)")
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }

    private func uploadOverrideRuns(_ overrideRuns: [NightscoutExercise]) async {
        guard !overrideRuns.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        do {
            for chunk in overrideRuns.chunks(ofCount: 100) {
                try await nightscout.uploadOverrides(Array(chunk))
            }

            // If successful, update the isUploadedToNS property of the OverrideRunStored objects
            await updateOverrideRunsAsUploaded(overrideRuns)

            debug(.nightscout, "Overrides uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func updateOverrideRunsAsUploaded(_ overrideRuns: [NightscoutExercise]) async {
        await backgroundContext.perform {
            let ids = overrideRuns.map(\.id) as NSArray
            print("\(DebuggingIdentifiers.inProgress) ids: \(ids)")
            let fetchRequest: NSFetchRequest<OverrideRunStored> = OverrideRunStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                print("\(DebuggingIdentifiers.inProgress) results: \(results)")
                for result in results {
                    result.isUploadedToNS = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToNS: \(error.userInfo)"
                )
            }
        }
    }
}

extension Array {
    func chunks(ofCount count: Int) -> [[Element]] {
        stride(from: 0, to: self.count, by: count).map {
            Array(self[$0 ..< Swift.min($0 + count, self.count)])
        }
    }
}

extension BaseNightscoutManager {
    /// listens for the notifications sent when the managedObjectContext has saved!
    func setupNotification() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: Notification.Name.NSManagedObjectContextDidSave,
            object: nil
        )
    }

    /// determine the actions when the context has changed
    ///
    /// its done on a background thread and after that the UI gets updated on the main thread
    @objc private func contextDidSave(_ notification: Notification) {
        guard let userInfo = notification.userInfo else {
            return
        }

        Task { [weak self] in
            await self?.processUpdates(userInfo: userInfo)
        }
    }

    private func processUpdates(userInfo: [AnyHashable: Any]) async {
        var objects = Set((userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? [])
        objects.formUnion((userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? [])
        objects.formUnion((userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? [])

        let manualGlucoseUpdates = objects.filter { $0 is GlucoseStored }
        let carbUpdates = objects.filter { $0 is CarbEntryStored }
        let pumpHistoryUpdates = objects.filter { $0 is PumpEventStored }
        let overrideUpdates = objects.filter { $0 is OverrideStored || $0 is OverrideRunStored }
        let determinationUpdates = objects.filter { $0 is OrefDetermination }

        if manualGlucoseUpdates.isNotEmpty {
            Task.detached {
                await self.uploadManualGlucose()
            }
        }
        if carbUpdates.isNotEmpty {
            Task.detached {
                await self.uploadCarbs()
            }
        }
        if pumpHistoryUpdates.isNotEmpty {
            Task.detached {
                await self.uploadPumpHistory()
            }
        }
        if overrideUpdates.isNotEmpty {
            Task.detached {
                await self.uploadOverrides()
            }
        }
//        if determinationUpdates.isNotEmpty {
//            Task.detached {
//                await self.uploadStatus()
//            }
//        }
    }
}
