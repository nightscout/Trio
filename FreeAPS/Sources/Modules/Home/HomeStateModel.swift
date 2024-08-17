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
        @Injected() var fetchGlucoseManager: FetchGlucoseManager!
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var determinationStorage: DeterminationStorage!
        @Injected() var glucoseStorage: GlucoseStorage!
        private let timer = DispatchTimer(timeInterval: 5)
        private(set) var filteredHours = 24
        @Published var manualGlucose: [BloodGlucose] = []
        @Published var announcement: [Announcement] = []
        @Published var uploadStats = false
        @Published var recentGlucose: BloodGlucose?
        @Published var maxBasal: Decimal = 2
        @Published var autotunedBasalProfile: [BasalProfileEntry] = []
        @Published var basalProfile: [BasalProfileEntry] = []
        @Published var tempTargets: [TempTarget] = []
        @Published var timerDate = Date()
        @Published var closedLoop = false
        @Published var pumpSuspended = false
        @Published var isLooping = false
        @Published var statusTitle = ""
        @Published var lastLoopDate: Date = .distantPast
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
        @Published var units: GlucoseUnits = .mgdL
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
        @Published var isLegendPresented: Bool = false
        @Published var legendSheetDetent = PresentationDetent.large
        @Published var tins: Bool = false
        @Published var isTempTargetActive: Bool = false
        @Published var roundedTotalBolus: String = ""
        @Published var selectedTab: Int = 0
        @Published var waitForSuggestion: Bool = false
        @Published var glucoseFromPersistence: [GlucoseStored] = []
        @Published var manualGlucoseFromPersistence: [GlucoseStored] = []
        @Published var carbsFromPersistence: [CarbEntryStored] = []
        @Published var fpusFromPersistence: [CarbEntryStored] = []
        @Published var determinationsFromPersistence: [OrefDetermination] = []
        @Published var enactedAndNonEnactedDeterminations: [OrefDetermination] = []
        @Published var insulinFromPersistence: [PumpEventStored] = []
        @Published var tempBasals: [PumpEventStored] = []
        @Published var suspensions: [PumpEventStored] = []
        @Published var batteryFromPersistence: [OpenAPS_Battery] = []
        @Published var lastPumpBolus: PumpEventStored?
        @Published var overrides: [OverrideStored] = []
        @Published var overrideRunStored: [OverrideRunStored] = []
        @Published var isOverrideCancelled: Bool = false
        @Published var preprocessedData: [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)] = []
        @Published var pumpStatusHighlightMessage: String? = nil
        @Published var cgmAvailable: Bool = false

        @Published var minForecast: [Int] = []
        @Published var maxForecast: [Int] = []
        @Published var minCount: Int = 12 // count of Forecasts drawn in 5 min distances, i.e. 12 means a min of 1 hour
        @Published var displayForecastsAsLines: Bool = false

        let context = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        private var coreDataObserver: CoreDataObserver?

        typealias PumpEvent = PumpEventStored.EventType

        override func subscribe() {
            setupNotification()
            coreDataObserver = CoreDataObserver()
            registerHandlers()
            setupGlucoseArray()
            setupManualGlucoseArray()
            setupCarbsArray()
            setupFPUsArray()
            setupDeterminationsArray()
            setupInsulinArray()
            setupLastBolus()
            setupBatteryArray()
            setupPumpSettings()
            setupBasalProfile()
            setupTempTargets()
            setupReservoir()
            setupAnnouncements()
            setupCurrentPumpTimezone()
            setupOverrides()
            setupOverrideRunStored()

            // TODO: isUploadEnabled the right var here??
            uploadStats = settingsManager.settings.isUploadEnabled
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
            cgmAvailable = fetchGlucoseManager.cgmGlucoseSourceType != CGMType.none

            displayForecastsAsLines = settingsManager.settings.displayForecastsAsLines

            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpSettingsObserver.self, observer: self)
            broadcaster.register(BasalProfileObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(PumpReservoirObserver.self, observer: self)
            broadcaster.register(PumpDeactivatedObserver.self, observer: self)

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
                        self.displayPumpStatusHighlightMessage()
                        self.setupBatteryArray()
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
                    } else if show {
                        self.router.mainSecondaryModalView.send(self.router.view(for: .pumpConfigDirect))
                    } else {
                        self.router.mainSecondaryModalView.send(nil)
                    }
                }
                .store(in: &lifetime)
        }

        private func registerHandlers() {
            coreDataObserver?.registerHandler(for: "OrefDetermination") { [weak self] in
                guard let self = self else { return }
                self.setupDeterminationsArray()
            }

            coreDataObserver?.registerHandler(for: "GlucoseStored") { [weak self] in
                guard let self = self else { return }
                self.setupGlucoseArray()
                self.setupManualGlucoseArray()
            }

            coreDataObserver?.registerHandler(for: "CarbEntryStored") { [weak self] in
                guard let self = self else { return }
                self.setupCarbsArray()
            }

            coreDataObserver?.registerHandler(for: "PumpEventStored") { [weak self] in
                guard let self = self else { return }
                self.setupInsulinArray()
                self.setupLastBolus()
                self.displayPumpStatusHighlightMessage()
            }

            coreDataObserver?.registerHandler(for: "OpenAPS_Battery") { [weak self] in
                guard let self = self else { return }
                self.setupBatteryArray()
            }

            coreDataObserver?.registerHandler(for: "OverrideStored") { [weak self] in
                guard let self = self else { return }
                self.setupOverrides()
            }

            coreDataObserver?.registerHandler(for: "OverrideRunStored") { [weak self] in
                guard let self = self else { return }
                self.setupOverrideRunStored()
            }
        }

        /// Display the eventual status message provided by the manager of the pump
        /// Only display if state is warning or critical message else return nil
        private func displayPumpStatusHighlightMessage(_ didDeactivate: Bool = false) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let statusHighlight = self.provider.deviceManager.pumpManager?.pumpStatusHighlight,
                   statusHighlight.state == .warning || statusHighlight.state == .critical, !didDeactivate
                {
                    pumpStatusHighlightMessage = (statusHighlight.state == .warning ? "⚠️\n" : "‼️\n") + statusHighlight
                        .localizedMessage
                } else {
                    pumpStatusHighlightMessage = nil
                }
            }
        }

        func runLoop() {
            provider.heartbeatNow()
        }

        func showProgressView() {
            glucoseStorage
                .isGlucoseDataFresh(glucoseFromPersistence.first?.date) ? (waitForSuggestion = true) : (waitForSuggestion = false)
        }

        func cancelBolus() {
            Task {
                await apsManager.cancelBolus()

                // perform determine basal sync, otherwise you have could end up with too much iob when opening the calculator again
                await apsManager.determineBasalSync()
            }
        }

        @MainActor func cancelOverride(withID id: NSManagedObjectID) async {
            do {
                let profileToCancel = try viewContext.existingObject(with: id) as? OverrideStored
                profileToCancel?.enabled = false

                await saveToOverrideRunStored(withID: id)

                guard viewContext.hasChanges else { return }
                try viewContext.save()

                Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel Profile")
            }
        }

        func calculateTINS() -> String {
            let startTime = calculateStartTime(hours: Int(hours))

            let totalBolus = calculateTotalBolus(from: insulinFromPersistence, since: startTime)
            let totalBasal = calculateTotalBasal(from: insulinFromPersistence, since: startTime)

            let totalInsulin = totalBolus + totalBasal

            return formatInsulinAmount(totalInsulin)
        }

        private func calculateStartTime(hours: Int) -> Date {
            let date = Date()
            let calendar = Calendar.current
            var offsetComponents = DateComponents()
            offsetComponents.hour = -hours
            return calendar.date(byAdding: offsetComponents, to: date)!
        }

        private func calculateTotalBolus(from events: [PumpEventStored], since startTime: Date) -> Double {
            let bolusEvents = events.filter { $0.timestamp ?? .distantPast >= startTime && $0.type == PumpEvent.bolus.rawValue }
            return bolusEvents.compactMap { $0.bolus?.amount?.doubleValue }.reduce(0, +)
        }

        private func calculateTotalBasal(from events: [PumpEventStored], since startTime: Date) -> Double {
            let basalEvents = events
                .filter { $0.timestamp ?? .distantPast >= startTime && $0.type == PumpEvent.tempBasal.rawValue }
                .sorted { $0.timestamp ?? .distantPast < $1.timestamp ?? .distantPast }

            var basalDurations: [Double] = []
            for (index, basalEntry) in basalEvents.enumerated() {
                if index + 1 < basalEvents.count {
                    let nextEntry = basalEvents[index + 1]
                    let durationInSeconds = nextEntry.timestamp?.timeIntervalSince(basalEntry.timestamp ?? Date()) ?? 0
                    basalDurations.append(durationInSeconds / 3600) // Conversion to hours
                }
            }

            return zip(basalEvents, basalDurations).map { entry, duration in
                guard let rate = entry.tempBasal?.rate?.doubleValue else { return 0 }
                return rate * duration
            }.reduce(0, +)
        }

        private func formatInsulinAmount(_ amount: Double) -> String {
            let roundedAmount = Decimal(round(100 * amount) / 100)
            return roundedAmount.formatted()
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
            router.mainSecondaryModalView.send(router.view(for: .cgmDirect))
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
    PumpSettingsObserver,
    BasalProfileObserver,
    TempTargetsObserver,
    PumpReservoirObserver,
    PumpTimeZoneObserver,
    PumpDeactivatedObserver
{
    // TODO: still needed?
    func glucoseDidUpdate(_: [BloodGlucose]) {
//        setupGlucose()
    }

    func determinationDidUpdate(_: Determination) {
        waitForSuggestion = false
    }

    func settingsDidChange(_ settings: FreeAPSSettings) {
        allowManualTemp = !settings.closedLoop
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
        displayForecastsAsLines = settingsManager.settings.displayForecastsAsLines
        tins = settingsManager.settings.tins
        cgmAvailable = (fetchGlucoseManager.cgmGlucoseSourceType != CGMType.none)
        displayPumpStatusHighlightMessage()
        setupBatteryArray()
    }

    // TODO: is this ever really triggered? react to MOC changes?
    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        displayPumpStatusHighlightMessage()
    }

    func pumpSettingsDidChange(_: PumpSettings) {
        setupPumpSettings()
        setupBatteryArray()
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) {
        setupBasalProfile()
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        setupTempTargets()
    }

    func pumpReservoirDidChange(_: Decimal) {
        setupReservoir()
        displayPumpStatusHighlightMessage()
    }

    func pumpDeactivatedDidChange() {
        displayPumpStatusHighlightMessage(true)
        batteryFromPersistence = []
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

// MARK: - Setup Core Data observation

extension Home.StateModel {
    /// listens for the notifications sent when the managedObjectContext has saved!
    func setupNotification() {
        /// custom notification that is sent when a batch insert of glucose objects is done
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBatchInsert),
            name: .didPerformBatchInsert,
            object: nil
        )

        /// custom notification that is sent when a batch delete of fpus is done
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBatchDelete),
            name: .didPerformBatchDelete,
            object: nil
        )
    }

    @objc private func handleBatchInsert() {
        setupFPUsArray()
        setupGlucoseArray()
    }

    @objc private func handleBatchDelete() {
        setupFPUsArray()
    }
}

// MARK: - Handle Core Data changes and update Arrays to display them in the UI

extension Home.StateModel {
    // Setup Glucose
    private func setupGlucoseArray() {
        Task {
            let ids = await self.fetchGlucose()
            let glucoseObjects: [GlucoseStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateGlucoseArray(with: glucoseObjects)
        }
    }

    private func fetchGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        return await context.perform {
            return results.map(\.objectID)
        }
    }

    @MainActor private func updateGlucoseArray(with objects: [GlucoseStored]) {
        glucoseFromPersistence = objects
    }

    // Setup Manual Glucose
    private func setupManualGlucoseArray() {
        Task {
            let ids = await self.fetchManualGlucose()
            let manualGlucoseObjects: [GlucoseStored] = await CoreDataStack.shared
                .getNSManagedObject(with: ids, context: viewContext)
            await updateManualGlucoseArray(with: manualGlucoseObjects)
        }
    }

    private func fetchManualGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.manualGlucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        return await context.perform {
            return results.map(\.objectID)
        }
    }

    @MainActor private func updateManualGlucoseArray(with objects: [GlucoseStored]) {
        manualGlucoseFromPersistence = objects
    }

    // Setup Carbs
    private func setupCarbsArray() {
        Task {
            let ids = await self.fetchCarbs()
            let carbObjects: [CarbEntryStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateCarbsArray(with: carbObjects)
        }
    }

    private func fetchCarbs() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.carbsForChart,
            key: "date",
            ascending: false
        )

        return await context.perform {
            return results.map(\.objectID)
        }
    }

    @MainActor private func updateCarbsArray(with objects: [CarbEntryStored]) {
        carbsFromPersistence = objects
    }

    // Setup FPUs
    private func setupFPUsArray() {
        Task {
            let ids = await self.fetchFPUs()
            let fpuObjects: [CarbEntryStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateFPUsArray(with: fpuObjects)
        }
    }

    private func fetchFPUs() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.fpusForChart,
            key: "date",
            ascending: false
        )

        return await context.perform {
            return results.map(\.objectID)
        }
    }

    @MainActor private func updateFPUsArray(with objects: [CarbEntryStored]) {
        fpusFromPersistence = objects
    }

    // Custom fetch to more efficiently filter only for cob and iob
    private func fetchCobAndIob() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.determinationsForCobIobCharts,
            key: "deliverAt",
            ascending: false,
            batchSize: 50,
            propertiesToFetch: ["cob", "iob", "deliverAt"]
        )

        return await context.perform {
            return results.map(\.objectID)
        }
    }

    // Setup Determinations
    private func setupDeterminationsArray() {
        Task {
            // Get the NSManagedObjectIDs
            async let enactedObjectIDs = determinationStorage
                .fetchLastDeterminationObjectID(predicate: NSPredicate.enactedDetermination)
            async let enactedAndNonEnactedObjectIDs = fetchCobAndIob()

            let enactedIDs = await enactedObjectIDs
            let enactedAndNonEnactedIDs = await enactedAndNonEnactedObjectIDs

            // Get the NSManagedObjects and return them on the Main Thread
            await updateDeterminationsArray(with: enactedIDs, keyPath: \.determinationsFromPersistence)
            await updateDeterminationsArray(with: enactedAndNonEnactedIDs, keyPath: \.enactedAndNonEnactedDeterminations)

            await updateForecastData()
        }
    }

    @MainActor private func updateDeterminationsArray(
        with IDs: [NSManagedObjectID],
        keyPath: ReferenceWritableKeyPath<Home.StateModel, [OrefDetermination]>
    ) async {
        // Fetch the objects off the main thread
        let determinationObjects: [OrefDetermination] = await CoreDataStack.shared
            .getNSManagedObject(with: IDs, context: viewContext)

        // Update the array on the main thread
        self[keyPath: keyPath] = determinationObjects
    }

    // Setup Insulin
    private func setupInsulinArray() {
        Task {
            let ids = await self.fetchInsulin()
            let insulinObjects: [PumpEventStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateInsulinArray(with: insulinObjects)
        }
    }

    private func fetchInsulin() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: true
        )

        return await context.perform {
            return results.map(\.objectID)
        }
    }

    @MainActor private func updateInsulinArray(with insulinObjects: [PumpEventStored]) {
        insulinFromPersistence = insulinObjects

        // Filter tempbasals
        manualTempBasal = apsManager.isManualTempBasal
        tempBasals = insulinFromPersistence.filter({ $0.tempBasal != nil })

        // Suspension and resume events
        suspensions = insulinFromPersistence.filter {
            $0.type == EventType.pumpSuspend.rawValue || $0.type == EventType.pumpResume.rawValue
        }
        let lastSuspension = suspensions.last

        pumpSuspended = tempBasals.last?.timestamp ?? Date() > lastSuspension?.timestamp ?? .distantPast && lastSuspension?
            .type == EventType.pumpSuspend.rawValue
    }

    // Setup Last Bolus to display the bolus progress bar
    // The predicate filters out all external boluses to prevent the progress bar from displaying the amount of an external bolus when an external bolus is added after a pump bolus
    private func setupLastBolus() {
        Task {
            guard let id = await self.fetchLastBolus() else { return }
            await updateLastBolus(with: id)
        }
    }

    private func fetchLastBolus() async -> NSManagedObjectID? {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.lastPumpBolus,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        return await context.perform {
            return results.map(\.objectID).first
        }
    }

    @MainActor private func updateLastBolus(with ID: NSManagedObjectID) {
        do {
            lastPumpBolus = try viewContext.existingObject(with: ID) as? PumpEventStored
        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the insulin array: \(error.localizedDescription)"
            )
        }
    }

    // Setup Battery
    private func setupBatteryArray() {
        Task {
            let ids = await self.fetchBattery()
            let batteryObjects: [OpenAPS_Battery] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateBatteryArray(with: batteryObjects)
        }
    }

    private func fetchBattery() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OpenAPS_Battery.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "date",
            ascending: false
        )

        return await context.perform {
            return results.map(\.objectID)
        }
    }

    @MainActor private func updateBatteryArray(with objects: [OpenAPS_Battery]) {
        batteryFromPersistence = objects
    }
}

extension Home.StateModel {
    // Setup Overrides
    private func setupOverrides() {
        Task {
            let ids = await self.fetchOverrides()
            let overrideObjects: [OverrideStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateOverrideArray(with: overrideObjects)
        }
    }

    private func fetchOverrides() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveOverride, // this predicate filters for all Overrides within the last 24h
            key: "date",
            ascending: false
        )

        return await context.perform {
            return results.map(\.objectID)
        }
    }

    @MainActor private func updateOverrideArray(with objects: [OverrideStored]) {
        overrides = objects
    }

    @MainActor func calculateDuration(override: OverrideStored) -> TimeInterval {
        guard let overrideDuration = override.duration as? Double, overrideDuration != 0 else {
            return TimeInterval(60 * 60 * 24) // one day
        }
        return TimeInterval(overrideDuration * 60) // return seconds
    }

    @MainActor func calculateTarget(override: OverrideStored) -> Decimal {
        guard let overrideTarget = override.target, overrideTarget != 0 else {
            return 100 // default
        }
        return overrideTarget.decimalValue
    }

    // Setup expired Overrides
    private func setupOverrideRunStored() {
        Task {
            let ids = await self.fetchOverrideRunStored()
            let overrideRunObjects: [OverrideRunStored] = await CoreDataStack.shared
                .getNSManagedObject(with: ids, context: viewContext)
            await updateOverrideRunStoredArray(with: overrideRunObjects)
        }
    }

    private func fetchOverrideRunStored() async -> [NSManagedObjectID] {
        let predicate = NSPredicate(format: "startDate >= %@", Date.oneDayAgo as NSDate)
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideRunStored.self,
            onContext: context,
            predicate: predicate,
            key: "startDate",
            ascending: false
        )

        return await context.perform {
            return results.map(\.objectID)
        }
    }

    @MainActor private func updateOverrideRunStoredArray(with objects: [OverrideRunStored]) {
        overrideRunStored = objects
    }

    @MainActor func saveToOverrideRunStored(withID id: NSManagedObjectID) async {
        await viewContext.perform {
            do {
                guard let object = try self.viewContext.existingObject(with: id) as? OverrideStored else { return }

                let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                newOverrideRunStored.id = UUID()
                newOverrideRunStored.name = object.name
                newOverrideRunStored.startDate = object.date ?? .distantPast
                newOverrideRunStored.endDate = Date()
                newOverrideRunStored.target = NSDecimalNumber(decimal: self.calculateTarget(override: object))
                newOverrideRunStored.override = object
                newOverrideRunStored.isUploadedToNS = false

            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to initialize a new Override Run Object")
            }
        }
    }
}

extension Home.StateModel {
    // Asynchronously preprocess forecast data in a background thread
    func preprocessForecastData() async -> [(id: UUID, forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID])] {
        await Task.detached { [self] () -> [(id: UUID, forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID])] in
            // Get the first determination ID from persistence
            guard let id = determinationsFromPersistence.first?.objectID else {
                return []
            }

            // Get the forecast IDs for the determination ID
            let forecastIDs = await determinationStorage.getForecastIDs(for: id, in: context)
            var result: [(id: UUID, forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID])] = []

            // Use a task group to fetch forecast value IDs concurrently
            await withTaskGroup(of: (UUID, NSManagedObjectID, [NSManagedObjectID]).self) { group in
                for forecastID in forecastIDs {
                    group.addTask {
                        let forecastValueIDs = await self.determinationStorage.getForecastValueIDs(
                            for: forecastID,
                            in: self.context
                        )
                        return (UUID(), forecastID, forecastValueIDs)
                    }
                }

                // Collect the results from the task group
                for await (uuid, forecastID, forecastValueIDs) in group {
                    result.append((id: uuid, forecastID: forecastID, forecastValueIDs: forecastValueIDs))
                }
            }

            return result
        }.value
    }

    // Fetch forecast values for a given data set
    func fetchForecastValues(
        for data: (id: UUID, forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID]),
        in context: NSManagedObjectContext
    ) async -> (UUID, Forecast?, [ForecastValue]) {
        var forecast: Forecast?
        var forecastValues: [ForecastValue] = []

        do {
            try await context.perform {
                // Fetch the forecast object
                forecast = try context.existingObject(with: data.forecastID) as? Forecast

                // Fetch the first 3h of forecast values
                for forecastValueID in data.forecastValueIDs.prefix(36) {
                    if let forecastValue = try context.existingObject(with: forecastValueID) as? ForecastValue {
                        forecastValues.append(forecastValue)
                    }
                }
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch forecast Values with error: \(error.localizedDescription)"
            )
        }

        return (data.id, forecast, forecastValues)
    }

    // Update forecast data and UI on the main thread
    @MainActor func updateForecastData() async {
        // Preprocess forecast data on a background thread
        let forecastData = await preprocessForecastData()

        var allForecastValues = [[ForecastValue]]()
        var preprocessedData = [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)]()

        // Use a task group to fetch forecast values concurrently
        await withTaskGroup(of: (UUID, Forecast?, [ForecastValue]).self) { group in
            for data in forecastData {
                group.addTask {
                    await self.fetchForecastValues(for: data, in: self.viewContext)
                }
            }

            // Collect the results from the task group
            for await (id, forecast, forecastValues) in group {
                guard let forecast = forecast, !forecastValues.isEmpty else { continue }

                allForecastValues.append(forecastValues)
                preprocessedData.append(contentsOf: forecastValues.map { (id: id, forecast: forecast, forecastValue: $0) })
            }
        }

        self.preprocessedData = preprocessedData

        // Ensure there are forecast values to process
        guard !allForecastValues.isEmpty else {
            minForecast = []
            maxForecast = []
            return
        }

        minCount = max(12, allForecastValues.map(\.count).min() ?? 0)
        guard minCount > 0 else { return }

        // Copy allForecastValues to a local constant for thread safety
        let localAllForecastValues = allForecastValues

        // Calculate min and max forecast values in a background task
        let (minResult, maxResult) = await Task.detached {
            let minForecast = (0 ..< self.minCount).map { index in
                localAllForecastValues.compactMap { $0.indices.contains(index) ? Int($0[index].value) : nil }.min() ?? 0
            }

            let maxForecast = (0 ..< self.minCount).map { index in
                localAllForecastValues.compactMap { $0.indices.contains(index) ? Int($0[index].value) : nil }.max() ?? 0
            }

            return (minForecast, maxForecast)
        }.value

        // Update the properties on the main thread
        minForecast = minResult
        maxForecast = maxResult
    }
}
