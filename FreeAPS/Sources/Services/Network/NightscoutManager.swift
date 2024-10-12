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
    func uploadProfiles() async
    func importSettings() async -> ScheduledNightscoutProfile?
    var cgmURL: URL? { get }
    func uploadNoteTreatment(note: String) async
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

    private let uploadOverridesSubject = PassthroughSubject<Void, Never>()
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

    private var isDownloadEnabled: Bool {
        settingsManager.settings.isDownloadEnabled
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

    private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: DispatchQueue.global(qos: .background))
                .share()
                .eraseToAnyPublisher()

        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.uploadGlucose()
                }
            }
            .store(in: &subscriptions)

        uploadOverridesSubject
            .debounce(for: .seconds(1), scheduler: DispatchQueue.global(qos: .background))
            .sink { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.uploadOverrides()
                }
            }
            .store(in: &subscriptions)

        registerHandlers()
        setupNotification()
    }

    private func subscribe() {
        broadcaster.register(TempTargetsObserver.self, observer: self)

        _ = reachabilityManager.startListening(onQueue: processQueue) { status in
            debug(.nightscout, "Network status: \(status)")
        }
    }

    private func registerHandlers() {
        coreDataPublisher?.filterByEntityName("OrefDetermination").sink { [weak self] _ in
            guard let self = self else { return }
            Task.detached {
                await self.uploadStatus()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("OverrideStored").sink { [weak self] _ in
            self?.uploadOverridesSubject.send()
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("OverrideRunStored").sink { [weak self] _ in
            self?.uploadOverridesSubject.send()
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("PumpEventStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task.detached {
                await self.uploadPumpHistory()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("CarbEntryStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task.detached {
                await self.uploadCarbs()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task.detached {
                await self.uploadManualGlucose()
            }
        }.store(in: &subscriptions)
    }

    func setupNotification() {
        Foundation.NotificationCenter.default.publisher(for: .willUpdateOverrideConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.uploadOverrides()

                    // Post a notification indicating that the upload has finished and that we can end the background task in the OverridePresetsIntentRequest
                    Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
                }
            }
            .store(in: &subscriptions)
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
        guard let nightscout = nightscoutAPI, isNetworkReachable, isDownloadEnabled else {
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
        guard let nightscout = nightscoutAPI, isNetworkReachable, isDownloadEnabled else {
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
        guard let nightscout = nightscoutAPI, isNetworkReachable, isDownloadEnabled else {
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

    private func fetchBattery() async -> Battery {
        await backgroundContext.perform {
            do {
                let results = try self.backgroundContext.fetch(OpenAPS_Battery.fetch(NSPredicate.predicateFor30MinAgo))
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

        // Suggested / Enacted
        async let enactedDeterminationID = determinationStorage
            .fetchLastDeterminationObjectID(predicate: NSPredicate.enactedDeterminationsNotYetUploadedToNightscout)
        async let suggestedDeterminationID = determinationStorage
            .fetchLastDeterminationObjectID(predicate: NSPredicate.suggestedDeterminationsNotYetUploadedToNightscout)

        // OpenAPS Status
        async let fetchedBattery = fetchBattery()
        async let fetchedReservoir = Decimal(from: storage.retrieveRawAsync(OpenAPS.Monitor.reservoir) ?? "0")
        async let fetchedIOBEntry = storage.retrieveAsync(OpenAPS.Monitor.iob, as: [IOBEntry].self)
        async let fetchedPumpStatus = storage.retrieveAsync(OpenAPS.Monitor.status, as: PumpStatus.self)

        var (fetchedEnactedDetermination, fetchedSuggestedDetermination) = await (
            determinationStorage.getOrefDeterminationNotYetUploadedToNightscout(enactedDeterminationID),
            determinationStorage.getOrefDeterminationNotYetUploadedToNightscout(suggestedDeterminationID)
        )

        // Guard to ensure both determinations are not nil
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

            if settingsManager.settings.units == .mmolL {
                suggestion.reason = parseReasonGlucoseValuesToMmolL(suggestion.reason)
            }
            // Check whether the last suggestion that was uploaded is the same that is fetched again when we are attempting to upload the enacted determination
            // Apparently we are too fast; so the flag update is not fast enough to have the predicate filter last suggestion out
            // If this check is truthy, set suggestion to nil so it's not uploaded again
            if let lastSuggested = lastSuggestedDetermination, lastSuggested.deliverAt == suggestion.deliverAt {
                modifiedSuggestedDetermination = nil
            } else {
                modifiedSuggestedDetermination = suggestion
            }
        }

        if let fetchedEnacted = fetchedEnactedDetermination, settingsManager.settings.units == .mmolL {
            var modifiedFetchedEnactedDetermination = fetchedEnactedDetermination
            modifiedFetchedEnactedDetermination?
                .reason = parseReasonGlucoseValuesToMmolL(fetchedEnacted.reason)

            modifiedFetchedEnactedDetermination?.bg = fetchedEnacted.bg?.asMmolL
            modifiedFetchedEnactedDetermination?.current_target = fetchedEnacted.current_target?.asMmolL
            modifiedFetchedEnactedDetermination?.minGuardBG = fetchedEnacted.minGuardBG?.asMmolL
            modifiedFetchedEnactedDetermination?.minPredBG = fetchedEnacted.minPredBG?.asMmolL
            modifiedFetchedEnactedDetermination?.threshold = fetchedEnacted.threshold?.asMmolL

            fetchedEnactedDetermination = modifiedFetchedEnactedDetermination
        }

        // Gather all relevant data for OpenAPS Status
        let iob = await fetchedIOBEntry
        let openapsStatus = OpenAPSStatus(
            iob: iob?.first,
            suggested: modifiedSuggestedDetermination,
            enacted: settingsManager.settings.closedLoop ? fetchedEnactedDetermination : nil,
            version: "0.7.1"
        )

        // Gather all relevant data for NS Status
        let battery = await fetchedBattery
        let reservoir = await fetchedReservoir
        let pumpStatus = await fetchedPumpStatus
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

        do {
            try await nightscout.uploadStatus(status)
            debug(.nightscout, "Status uploaded")

            if let enacted = fetchedEnactedDetermination {
                await updateOrefDeterminationAsUploaded([enacted])
            }

            if let suggested = fetchedSuggestedDetermination {
                await updateOrefDeterminationAsUploaded([suggested])
            }

            lastEnactedDetermination = fetchedEnactedDetermination
            lastSuggestedDetermination = fetchedSuggestedDetermination

            debug(.nightscout, "NSDeviceStatus with Determination uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }

        Task.detached {
            await self.uploadPodAge()
        }
    }

    private func updateOrefDeterminationAsUploaded(_ determination: [Determination]) async {
        await backgroundContext.perform {
            let ids = determination.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<OrefDetermination> = OrefDetermination.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
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

    func uploadProfiles() async {
        if isUploadEnabled {
            do {
                guard let sensitivities = await storage.retrieveAsync(
                    OpenAPS.Settings.insulinSensitivities,
                    as: InsulinSensitivities.self
                ) else {
                    debug(.nightscout, "NightscoutManager uploadProfile: error loading insulinSensitivities")
                    return
                }
                guard let targets = await storage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self) else {
                    debug(.nightscout, "NightscoutManager uploadProfile: error loading bgTargets")
                    return
                }
                guard let carbRatios = await storage.retrieveAsync(OpenAPS.Settings.carbRatios, as: CarbRatios.self) else {
                    debug(.nightscout, "NightscoutManager uploadProfile: error loading carbRatios")
                    return
                }
                guard let basalProfile = await storage.retrieveAsync(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                else {
                    debug(.nightscout, "NightscoutManager uploadProfile: error loading basalProfile")
                    return
                }

                let shouldParseToMmolL = settingsManager.settings.units == .mmolL

                let sens = sensitivities.sensitivities.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: !shouldParseToMmolL ? item.sensitivity : item.sensitivity.asMmolL,
                        timeAsSeconds: item.offset * 60
                    )
                }
                let targetLow = targets.targets.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: !shouldParseToMmolL ? item.low : item.low.asMmolL,
                        timeAsSeconds: item.offset * 60
                    )
                }
                let targetHigh = targets.targets.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: !shouldParseToMmolL ? item.high : item.high.asMmolL,
                        timeAsSeconds: item.offset * 60
                    )
                }
                let cr = carbRatios.schedule.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: item.ratio,
                        timeAsSeconds: item.offset * 60
                    )
                }
                let basal = basalProfile.map { item in
                    NightscoutTimevalue(
                        time: String(item.start.prefix(5)),
                        value: item.rate,
                        timeAsSeconds: item.minutes * 60
                    )
                }

                let nsUnits: String = {
                    switch settingsManager.settings.units {
                    case .mgdL:
                        return "mg/dl"
                    case .mmolL:
                        return "mmol"
                    }
                }()

                var carbsHr: Decimal = 0
                if let isf = sensitivities.sensitivities.map(\.sensitivity).first,
                   let cr = carbRatios.schedule.map(\.ratio).first,
                   isf > 0, cr > 0
                {
                    carbsHr = settingsManager.preferences.min5mCarbimpact * 12 / isf * cr
                    if settingsManager.settings.units == .mmolL {
                        carbsHr *= GlucoseUnits.exchangeRate
                    }
                    carbsHr = Decimal(round(Double(carbsHr) * 10.0)) / 10
                }

                let scheduledProfile = ScheduledNightscoutProfile(
                    dia: settingsManager.pumpSettings.insulinActionCurve,
                    carbs_hr: Int(carbsHr),
                    delay: 0,
                    timezone: TimeZone.current.identifier,
                    target_low: targetLow,
                    target_high: targetHigh,
                    sens: sens,
                    basal: basal,
                    carbratio: cr,
                    units: nsUnits
                )
                let defaultProfile = "default"

                let now = Date()

                let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
                let deviceToken = UserDefaults.standard.string(forKey: "deviceToken") ?? ""
                let isAPNSProduction = UserDefaults.standard.bool(forKey: "isAPNSProduction")
                let presetOverrides = await overridesStorage.getPresetOverridesForNightscout()

                let profileStore = NightscoutProfileStore(
                    defaultProfile: defaultProfile,
                    startDate: now,
                    mills: Int(now.timeIntervalSince1970) * 1000,
                    units: nsUnits,
                    enteredBy: NightscoutTreatment.local,
                    store: [defaultProfile: scheduledProfile],
                    bundleIdentifier: bundleIdentifier,
                    deviceToken: deviceToken,
                    isAPNSProduction: isAPNSProduction,
                    overrides: presetOverrides
                )

                guard let nightscout = nightscoutAPI, isNetworkReachable else {
                    if !isNetworkReachable {
                        debug(.nightscout, "Network issues; aborting upload")
                    }
                    debug(.nightscout, "Nightscout API service not available; aborting upload")
                    return
                }

                do {
                    try await nightscout.uploadProfile(profileStore)
                    debug(.nightscout, "Profile uploaded")
                } catch {
                    debug(.nightscout, "NightscoutManager uploadProfile: \(error.localizedDescription)")
                }
            }
        } else {
            debug(.nightscout, "Upload to NS disabled; aborting profile uploaded")
        }
    }

    func importSettings() async -> ScheduledNightscoutProfile? {
        guard let nightscout = nightscoutAPI else {
            debug(.nightscout, "NS API not available. Aborting NS Status upload.")
            return nil
        }

        do {
            return try await nightscout.importSettings()
        } catch {
            debug(.nightscout, error.localizedDescription)
            return nil
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
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
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
            let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
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
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
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
            let fetchRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
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
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
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
            let fetchRequest: NSFetchRequest<OverrideRunStored> = OverrideRunStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
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

    func uploadNoteTreatment(note: String) async {
        let uploadedNotes = storage.retrieve(OpenAPS.Nightscout.uploadedNotes, as: [NightscoutTreatment].self) ?? []
        let now = Date()

        if uploadedNotes.last?.notes != note || (uploadedNotes.last?.createdAt ?? .distantPast) != now {
            let noteTreatment = NightscoutTreatment(
                eventType: .nsNote,
                createdAt: now,
                enteredBy: NightscoutTreatment.local,
                notes: note,
                targetTop: nil,
                targetBottom: nil
            )
            await uploadTreatments([noteTreatment], fileToSave: OpenAPS.Nightscout.uploadedNotes)
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

extension BaseNightscoutManager: TempTargetsObserver {
    func tempTargetsDidUpdate(_: [TempTarget]) {
        Task.detached {
            await self.uploadTempTargets()
        }
    }
}

extension BaseNightscoutManager {
    /**
     Converts glucose-related values in the given `reason` string to mmol/L, including ranges (e.g., `ISF: 54→54`), comparisons (e.g., `maxDelta 37 > 20% of BG 95`), and both positive and negative values (e.g., `Dev: -36`).

     - Parameters:
       - reason: The string containing glucose-related values to be converted.

     - Returns:
       A string with glucose values converted to mmol/L.

     - Glucose tags handled: `ISF:`, `Target:`, `minPredBG`, `minGuardBG`, `IOBpredBG`, `COBpredBG`, `UAMpredBG`, `Dev:`, `maxDelta`, `BG`.
     */
    func parseReasonGlucoseValuesToMmolL(_ reason: String) -> String {
        // Updated pattern to handle cases like minGuardBG 34, minGuardBG 34<70, and "maxDelta 37 > 20% of BG 95", and ensure "Target:" is handled correctly
        let pattern =
            "(ISF:\\s*-?\\d+→-?\\d+|Dev:\\s*-?\\d+|Target:\\s*-?\\d+|(?:minPredBG|minGuardBG|IOBpredBG|COBpredBG|UAMpredBG|maxDelta|BG)\\s*-?\\d+(?:<\\d+)?(?:>\\s*\\d+%\\s*of\\s*BG\\s*\\d+)?)"

        let regex = try! NSRegularExpression(pattern: pattern)

        func convertToMmolL(_ value: String) -> String {
            if let glucoseValue = Double(value.replacingOccurrences(of: "[^\\d.-]", with: "", options: .regularExpression)) {
                return glucoseValue.asMmolL.description
            }
            return value
        }

        let matches = regex.matches(in: reason, range: NSRange(reason.startIndex..., in: reason))
        var updatedReason = reason

        for match in matches.reversed() {
            if let range = Range(match.range, in: reason) {
                let glucoseValueString = String(reason[range])

                if glucoseValueString.contains("→") {
                    // Handle ISF case with an arrow (e.g., ISF: 54→54)
                    let values = glucoseValueString.components(separatedBy: "→")
                    let firstValue = convertToMmolL(values[0])
                    let secondValue = convertToMmolL(values[1])
                    let formattedGlucoseValueString = "\(values[0].components(separatedBy: ":")[0]): \(firstValue)→\(secondValue)"
                    updatedReason.replaceSubrange(range, with: formattedGlucoseValueString)
                } else if glucoseValueString.contains("<") {
                    // Handle range case for minGuardBG like "minGuardBG 34<70"
                    let values = glucoseValueString.components(separatedBy: "<")
                    let firstValue = convertToMmolL(values[0])
                    let secondValue = convertToMmolL(values[1])
                    let formattedGlucoseValueString = "\(values[0].components(separatedBy: ":")[0]) \(firstValue)<\(secondValue)"
                    updatedReason.replaceSubrange(range, with: formattedGlucoseValueString)
                } else if glucoseValueString.contains(">"), glucoseValueString.contains("BG") {
                    // Handle cases like "maxDelta 37 > 20% of BG 95"
                    let pattern = "(\\d+) > \\d+% of BG (\\d+)"
                    let matches = try! NSRegularExpression(pattern: pattern)
                        .matches(in: glucoseValueString, range: NSRange(glucoseValueString.startIndex..., in: glucoseValueString))

                    if let match = matches.first, match.numberOfRanges == 3 {
                        let firstValueRange = Range(match.range(at: 1), in: glucoseValueString)!
                        let secondValueRange = Range(match.range(at: 2), in: glucoseValueString)!

                        let firstValue = convertToMmolL(String(glucoseValueString[firstValueRange]))
                        let secondValue = convertToMmolL(String(glucoseValueString[secondValueRange]))

                        let formattedGlucoseValueString = glucoseValueString.replacingOccurrences(
                            of: "\(glucoseValueString[firstValueRange]) > 20% of BG \(glucoseValueString[secondValueRange])",
                            with: "\(firstValue) > 20% of BG \(secondValue)"
                        )
                        updatedReason.replaceSubrange(range, with: formattedGlucoseValueString)
                    }
                } else {
                    // General case for single glucose values like "Target: 100" or "minGuardBG 34"
                    let parts = glucoseValueString.components(separatedBy: CharacterSet(charactersIn: ": "))
                    let formattedValue = convertToMmolL(parts.last!.trimmingCharacters(in: .whitespaces))
                    updatedReason.replaceSubrange(range, with: "\(parts[0]): \(formattedValue)")
                }
            }
        }

        return updatedReason
    }
}
