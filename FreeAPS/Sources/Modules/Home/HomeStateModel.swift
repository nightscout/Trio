import Combine
import CoreData
import Foundation
import LoopKitUI
import SwiftDate
import SwiftUI

extension Home {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var apsManager: APSManager!
        @Injected() var nightscoutManager: NightscoutManager!
        private let timer = DispatchTimer(timeInterval: 5)
        private(set) var filteredHours = 24
        @Published var manualGlucose: [BloodGlucose] = []
        @Published var announcement: [Announcement] = []
        @Published var uploadStats = false
        @Published var recentGlucose: BloodGlucose?
        @Published var tempBasals: [PumpHistoryEvent] = []
        @Published var boluses: [PumpHistoryEvent] = []
        @Published var suspensions: [PumpHistoryEvent] = []
        @Published var maxBasal: Decimal = 2
        @Published var autotunedBasalProfile: [BasalProfileEntry] = []
        @Published var basalProfile: [BasalProfileEntry] = []
        @Published var tempTargets: [TempTarget] = []
        @Published var glucoseFromPersistence: [GlucoseStored] = []
        @Published var determinationsFromPersistence: [NSManagedObjectID] = []
        @Published var carbsFromPersistence: [CarbEntryStored] = []
        @Published var fpusFromPersistence: [CarbEntryStored] = []
        @Published var timerDate = Date()
        @Published var closedLoop = false
        @Published var pumpSuspended = false
        @Published var isLooping = false
        @Published var statusTitle = ""
        @Published var lastLoopDate: Date = .distantPast
        @Published var tempRate: Decimal?
        @Published var battery: Battery?
        @Published var reservoir: Decimal?
        @Published var pumpName = ""
        @Published var pumpExpiresAtDate: Date?
        @Published var tempTarget: TempTarget?
        @Published var setupPump = false
        @Published var errorMessage: String? = nil
        @Published var errorDate: Date? = nil
        @Published var bolusProgress: Decimal?
        @Published var eventualBG: Int?
        @Published var allowManualTemp = false
        @Published var units: GlucoseUnits = .mmolL
        @Published var pumpDisplayState: PumpDisplayState?
        @Published var alarm: GlucoseAlarm?
        @Published var animatedBackground = false
        @Published var manualTempBasal = false
        @Published var smooth = false
        @Published var maxValue: Decimal = 1.2
        @Published var lowGlucose: Decimal = 4 / 0.0555
        @Published var highGlucose: Decimal = 10 / 0.0555
        @Published var overrideUnit: Bool = false
        @Published var displayXgridLines: Bool = false
        @Published var displayYgridLines: Bool = false
        @Published var thresholdLines: Bool = false
        @Published var timeZone: TimeZone?
        @Published var hours: Int16 = 6
        @Published var totalBolus: Decimal = 0

        @Published var isStatusPopupPresented: Bool = false
        @Published var tins: Bool = false
        @Published var isTempTargetActive: Bool = false

        @Published var roundedTotalBolus: String = ""

        @Published var selectedTab: Int = 0

        @Published var waitForSuggestion: Bool = false

        let context = CoreDataStack.shared.backgroundContext

        override func subscribe() {
            setupBasals()
            setupBoluses()
            setupSuspensions()
            setupPumpSettings()
            setupBasalProfile()
            setupTempTargets()
            setupReservoir()
            setupAnnouncements()
            setupCurrentPumpTimezone()
            setupNotification()

            Task {
                await updateGlucose()
                await updateDetermination()
                await updateCarbs()
                await updateFpus()
            }

            uploadStats = settingsManager.settings.uploadStats
            units = settingsManager.settings.units
            allowManualTemp = !settingsManager.settings.closedLoop
            closedLoop = settingsManager.settings.closedLoop
            lastLoopDate = apsManager.lastLoopDate
            alarm = provider.glucoseStorage.alarm
            manualTempBasal = apsManager.isManualTempBasal
            setupCurrentTempTarget()
            smooth = settingsManager.settings.smoothGlucose
            maxValue = settingsManager.preferences.autosensMax
            lowGlucose = settingsManager.settings.low
            highGlucose = settingsManager.settings.high
            overrideUnit = settingsManager.settings.overrideHbA1cUnit
            displayXgridLines = settingsManager.settings.xGridLines
            displayYgridLines = settingsManager.settings.yGridLines
            thresholdLines = settingsManager.settings.rulerMarks
            tins = settingsManager.settings.tins

            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(PumpSettingsObserver.self, observer: self)
            broadcaster.register(BasalProfileObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(PumpReservoirObserver.self, observer: self)

            animatedBackground = settingsManager.settings.animatedBackground

            timer.eventHandler = {
                DispatchQueue.main.async { [weak self] in
                    self?.timerDate = Date()
                    self?.setupCurrentTempTarget()
                }
            }
            timer.resume()

            apsManager.isLooping
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.isLooping, on: self)
                .store(in: &lifetime)

            apsManager.lastLoopDateSubject
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.lastLoopDate, on: self)
                .store(in: &lifetime)

            apsManager.pumpName
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.pumpName, on: self)
                .store(in: &lifetime)

            apsManager.pumpExpiresAtDate
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.pumpExpiresAtDate, on: self)
                .store(in: &lifetime)

            apsManager.lastError
                .receive(on: DispatchQueue.main)
                .map { [weak self] error in
                    self?.errorDate = error == nil ? nil : Date()
                    if let error = error {
                        info(.default, error.localizedDescription)
                    }
                    return error?.localizedDescription
                }
                .weakAssign(to: \.errorMessage, on: self)
                .store(in: &lifetime)

            apsManager.bolusProgress
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.bolusProgress, on: self)
                .store(in: &lifetime)

            apsManager.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    self.pumpDisplayState = state
                    if state == nil {
                        self.reservoir = nil
                        self.battery = nil
                        self.pumpName = ""
                        self.pumpExpiresAtDate = nil
                        self.setupPump = false
                    } else {
                        self.setupReservoir()
                    }
                }
                .store(in: &lifetime)

            $setupPump
                .sink { [weak self] show in
                    guard let self = self else { return }
                    if show, let pumpManager = self.provider.apsManager.pumpManager,
                       let bluetoothProvider = self.provider.apsManager.bluetoothManager
                    {
                        let view = PumpConfig.PumpSettingsView(
                            pumpManager: pumpManager,
                            bluetoothManager: bluetoothProvider,
                            completionDelegate: self,
                            setupDelegate: self
                        ).asAny()
                        self.router.mainSecondaryModalView.send(view)
                    } else {
                        self.router.mainSecondaryModalView.send(nil)
                    }
                }
                .store(in: &lifetime)
        }

        /// listens for the notifications sent when the managedObjectContext has changed
        func setupNotification() {
            Foundation.NotificationCenter.default.addObserver(
                self,
                selector: #selector(contextDidSave(_:)),
                name: Notification.Name.NSManagedObjectContextObjectsDidChange,
                object: context
            )
        }

        /// determine the actions when the context has changed
        ///
        /// its done on a background thread and after that the UI gets updated on the main thread
        @objc private func contextDidSave(_ notification: Notification) {
            guard let userInfo = notification.userInfo else { return }

            Task { [weak self] in
                await self?.processUpdates(userInfo: userInfo)
            }
        }

        private func processUpdates(userInfo: [AnyHashable: Any]) async {
            var objects = Set((userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? [])
            objects.formUnion((userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? [])
            objects.formUnion((userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? [])

            let glucoseUpdates = objects.filter { $0 is GlucoseStored }
            let determinationUpdates = objects.filter { $0 is OrefDetermination }
            let carbUpdates = objects.filter { $0 is CarbEntryStored }

            if glucoseUpdates.isNotEmpty {
                await updateGlucose()
            }
            if determinationUpdates.isNotEmpty {
                await updateDetermination()
            }
            if carbUpdates.isNotEmpty {
                await updateCarbs()
                await updateFpus()
            }
        }

        /// wait for the fetch to complete and then update the UI on the main thread
        private func updateGlucose() async {
            let results = await fetchGlucoseInBackground()
            await MainActor.run {
                glucoseFromPersistence = results
            }
        }

        private func updateDetermination() async {
            let results = await fetchDeterminationInBackground()
            let ids = results.map(\.objectID)
            await MainActor.run {
                determinationsFromPersistence = ids
            }
        }

        private func updateCarbs() async {
            let results = await fetchCarbsInBackground()
            await MainActor.run {
                carbsFromPersistence = results
            }
        }

        private func updateFpus() async {
            let results = await fetchFpusInBackground()
            await MainActor.run {
                fpusFromPersistence = results
            }
        }

        /// do the heavy fetch operation in the background
        private func fetchGlucoseInBackground() async -> [GlucoseStored] {
            await withCheckedContinuation { continuation in
                context.perform {
                    let results = self.provider.fetchGlucose()
                    continuation.resume(returning: results)
                }
            }
        }

        private func fetchDeterminationInBackground() async -> [OrefDetermination] {
            await withCheckedContinuation { continuation in
                context.perform {
                    let results = CoreDataStack.shared.fetchEntities(
                        ofType: OrefDetermination.self,
                        predicate: NSPredicate.enactedDetermination,
                        key: "deliverAt",
                        ascending: false,
                        fetchLimit: 1
                    )
                    continuation.resume(returning: results)
                }
            }
        }

        private func fetchCarbsInBackground() async -> [CarbEntryStored] {
            await withCheckedContinuation { continuation in
                context.perform {
                    let results = CoreDataStack.shared.fetchEntities(
                        ofType: CarbEntryStored.self,
                        predicate: NSPredicate.carbsForChart,
                        key: "date",
                        ascending: false,
                        batchSize: 20
                    )
                    continuation.resume(returning: results)
                }
            }
        }

        private func fetchFpusInBackground() async -> [CarbEntryStored] {
            await withCheckedContinuation { continuation in
                context.perform {
                    let results = CoreDataStack.shared.fetchEntities(
                        ofType: CarbEntryStored.self,
                        predicate: NSPredicate.fpusForChart,
                        key: "date",
                        ascending: false,
                        batchSize: 20
                    )
                    continuation.resume(returning: results)
                }
            }
        }

        func runLoop() {
            provider.heartbeatNow()
        }

        func cancelBolus() {
            apsManager.cancelBolus()

            // perform determine basal sync, otherwise you have could end up with too much iob when opening the calculator again
            apsManager.determineBasalSync()
        }

        func cancelProfile() {
            context.perform { [self] in
                let profiles = Override(context: self.context)
                profiles.enabled = false
                profiles.date = Date()

                do {
                    try CoreDataStack.shared.saveContext()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }

        private func setupBasals() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.manualTempBasal = self.apsManager.isManualTempBasal
                self.tempBasals = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .tempBasal || $0.type == .tempBasalDuration
                }
                let lastTempBasal = Array(self.tempBasals.suffix(2))
                guard lastTempBasal.count == 2 else {
                    self.tempRate = nil
                    return
                }

                guard let lastRate = lastTempBasal[0].rate, let lastDuration = lastTempBasal[1].durationMin else {
                    self.tempRate = nil
                    return
                }
                let lastDate = lastTempBasal[0].timestamp
                guard Date().timeIntervalSince(lastDate.addingTimeInterval(lastDuration.minutes.timeInterval)) < 0 else {
                    self.tempRate = nil
                    return
                }
                self.tempRate = lastRate
            }
        }

        private func setupBoluses() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.boluses = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .bolus
                }
            }
        }

        func calculateTINS() -> String {
            let date = Date()
            let calendar = Calendar.current
            let offset = hours

            var offsetComponents = DateComponents()
            offsetComponents.hour = -Int(offset)
            let startTime = calendar.date(byAdding: offsetComponents, to: date)!

            let bolusesForCurrentDay = boluses.filter { $0.timestamp >= startTime && $0.type == .bolus }
            let totalBolus = bolusesForCurrentDay.map { $0.amount ?? 0 }.reduce(0, +)
            roundedTotalBolus = Decimal(round(100 * Double(totalBolus)) / 100).formatted()

            return roundedTotalBolus
        }

        private func setupSuspensions() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.suspensions = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .pumpSuspend || $0.type == .pumpResume
                }

                let last = self.suspensions.last
                let tbr = self.tempBasals.first { $0.timestamp > (last?.timestamp ?? .distantPast) }

                self.pumpSuspended = tbr == nil && last?.type == .pumpSuspend
            }
        }

        private func setupPumpSettings() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.maxBasal = self.provider.pumpSettings().maxBasal
            }
        }

        private func setupBasalProfile() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.autotunedBasalProfile = self.provider.autotunedBasalProfile()
                self.basalProfile = self.provider.basalProfile()
            }
        }

        private func setupTempTargets() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.manualTempBasal = self.apsManager.isManualTempBasal
                self.tempTargets = self.provider.tempTargets(hours: self.filteredHours)
            }
        }

        private func setupAnnouncements() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.announcement = self.provider.announcement(self.filteredHours)
            }
        }

        private func setupReservoir() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.reservoir = self.provider.pumpReservoir()
            }
        }

        private func setupCurrentTempTarget() {
            tempTarget = provider.tempTarget()
        }

        private func setupCurrentPumpTimezone() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.timeZone = self.provider.pumpTimeZone()
            }
        }

        func openCGM() {
            guard var url = nightscoutManager.cgmURL else { return }

            switch url.absoluteString {
            case "http://127.0.0.1:1979":
                url = URL(string: "spikeapp://")!
            case "http://127.0.0.1:17580":
                url = URL(string: "diabox://")!
            case CGMType.libreTransmitter.appURL?.absoluteString:
                showModal(for: .libreConfig)
            default: break
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }

        func infoPanelTTPercentage(_ hbt_: Double, _ target: Decimal) -> Decimal {
            guard hbt_ != 0 || target != 0 else {
                return 0
            }
            let c = Decimal(hbt_ - 100)
            let ratio = min(c / (target + c - 100), maxValue)
            return (ratio * 100)
        }
    }
}

extension Home.StateModel:
    GlucoseObserver,
    DeterminationObserver,
    SettingsObserver,
    PumpHistoryObserver,
    PumpSettingsObserver,
    BasalProfileObserver,
    TempTargetsObserver,
    PumpReservoirObserver,
    PumpTimeZoneObserver
{
    func glucoseDidUpdate(_: [BloodGlucose]) {
//        setupGlucose()
    }

    func determinationDidUpdate(_: Determination) {
        waitForSuggestion = false
    }

    func settingsDidChange(_ settings: FreeAPSSettings) {
        allowManualTemp = !settings.closedLoop
        uploadStats = settingsManager.settings.uploadStats
        closedLoop = settingsManager.settings.closedLoop
        units = settingsManager.settings.units
        animatedBackground = settingsManager.settings.animatedBackground
        manualTempBasal = apsManager.isManualTempBasal
        smooth = settingsManager.settings.smoothGlucose
        lowGlucose = settingsManager.settings.low
        highGlucose = settingsManager.settings.high
        overrideUnit = settingsManager.settings.overrideHbA1cUnit
        displayXgridLines = settingsManager.settings.xGridLines
        displayYgridLines = settingsManager.settings.yGridLines
        thresholdLines = settingsManager.settings.rulerMarks
        tins = settingsManager.settings.tins
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupBasals()
        setupBoluses()
        setupSuspensions()
        setupAnnouncements()
    }

    func pumpSettingsDidChange(_: PumpSettings) {
        setupPumpSettings()
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) {
        setupBasalProfile()
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        setupTempTargets()
    }

    func pumpReservoirDidChange(_: Decimal) {
        setupReservoir()
    }

    func pumpTimeZoneDidChange(_: TimeZone) {
        setupCurrentPumpTimezone()
    }
}

extension Home.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}

extension Home.StateModel: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        provider.apsManager.pumpManager = pumpManager
        if let insulinType = pumpManager.status.insulinType {
            settingsManager.updateInsulinCurve(insulinType)
        }
    }

    func pumpManagerOnboarding(didOnboardPumpManager _: PumpManagerUI) {
        // nothing to do
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {
        // TODO:
    }
}
