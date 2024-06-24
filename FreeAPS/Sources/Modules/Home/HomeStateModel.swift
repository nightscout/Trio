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

        @Published var glucoseFromPersistence: [GlucoseStored] = []
        @Published var manualGlucoseFromPersistence: [GlucoseStored] = []
        @Published var carbsFromPersistence: [CarbEntryStored] = []
        @Published var fpusFromPersistence: [CarbEntryStored] = []
        @Published var determinationsFromPersistence: [OrefDetermination] = []
        @Published var enactedAndNonEnactedDeterminations: [OrefDetermination] = []
        @Published var insulinFromPersistence: [PumpEventStored] = []
        @Published var tempBasals: [PumpEventStored] = []
        var boluses: [PumpEventStored] = []
        @Published var suspensions: [PumpEventStored] = []
        @Published var batteryFromPersistence: [OpenAPS_Battery] = []
        @Published var lastPumpBolus: PumpEventStored?

        let context = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() {
            setupNotification()
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

        func runLoop() {
            provider.heartbeatNow()
        }

        func cancelBolus() {
            Task {
                await apsManager.cancelBolus()

                // perform determine basal sync, otherwise you have could end up with too much iob when opening the calculator again
                await apsManager.determineBasalSync()
            }
        }

        @MainActor func cancelProfile(withID id: NSManagedObjectID) async {
            do {
                let profileToCancel = try viewContext.existingObject(with: id) as? OverrideStored
                profileToCancel?.enabled = false
                profileToCancel?.date = Date()

                guard viewContext.hasChanges else { return }
                try viewContext.save()
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel Profile")
            }
        }

        func calculateTINS() -> String {
            let date = Date()
            let calendar = Calendar.current
            let offset = hours

            var offsetComponents = DateComponents()
            offsetComponents.hour = -Int(offset)
            let startTime = calendar.date(byAdding: offsetComponents, to: date)!

            let bolusesForCurrentDay = boluses.filter { $0.timestamp ?? .distantPast >= startTime }
            let totalBolus = bolusesForCurrentDay.map { Double($0.bolus?.amount ?? 0.0) }.reduce(0.0, +)
            roundedTotalBolus = Decimal(round(100 * Double(totalBolus)) / 100).formatted()

            return roundedTotalBolus
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

//    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
//        setupAnnouncements()
//    }

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

// MARK: - Setup Core Data observation

extension Home.StateModel {
    /// listens for the notifications sent when the managedObjectContext has saved!
    func setupNotification() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: Notification.Name.NSManagedObjectContextDidSave,
            object: nil
        )

        /// custom notification that is sent when a batch insert of glucose objects is done
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBatchInsert),
            name: .didPerformBatchInsert,
            object: nil
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

    @objc private func handleBatchInsert() {
        setupGlucoseArray()
    }

    private func processUpdates(userInfo: [AnyHashable: Any]) async {
        var objects = Set((userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? [])
        objects.formUnion((userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? [])
        objects.formUnion((userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? [])

        let glucoseUpdates = objects.filter { $0 is GlucoseStored }
        let manualGlucoseUpdates = objects.filter { $0 is GlucoseStored }
        let determinationUpdates = objects.filter { $0 is OrefDetermination }
        let carbUpdates = objects.filter { $0 is CarbEntryStored }
        let insulinUpdates = objects.filter { $0 is PumpEventStored }
        let batteryUpdates = objects.filter { $0 is OpenAPS_Battery }

        DispatchQueue.global(qos: .background).async {
            if !glucoseUpdates.isEmpty {
                self.setupGlucoseArray()
            }
            if !manualGlucoseUpdates.isEmpty {
                self.setupManualGlucoseArray()
            }
            if !determinationUpdates.isEmpty {
                self.setupDeterminationsArray()
            }
            if !carbUpdates.isEmpty {
                self.setupCarbsArray()
                self.setupFPUsArray()
            }
            if !insulinUpdates.isEmpty {
                self.setupInsulinArray()
                self.setupLastBolus()
            }
            if !batteryUpdates.isEmpty {
                self.setupBatteryArray()
            }
        }
    }
}

// MARK: - Handle Core Data changes and update Arrays to display them in the UI

extension Home.StateModel {
    // Setup Glucose
    private func setupGlucoseArray() {
        Task {
            let ids = await self.fetchGlucose()
            await updateGlucoseArray(with: ids)
        }
    }

    private func fetchGlucose() async -> [NSManagedObjectID] {
        CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        ).map(\.objectID)
    }

    @MainActor private func updateGlucoseArray(with IDs: [NSManagedObjectID]) {
        do {
            let glucoseObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? GlucoseStored
            }
            glucoseFromPersistence = glucoseObjects
        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the glucose array: \(error.localizedDescription)"
            )
        }
    }

    // Setup Manual Glucose
    private func setupManualGlucoseArray() {
        Task {
            let ids = await self.fetchManualGlucose()
            await updateManualGlucoseArray(with: ids)
        }
    }

    private func fetchManualGlucose() async -> [NSManagedObjectID] {
        CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.manualGlucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        ).map(\.objectID)
    }

    @MainActor private func updateManualGlucoseArray(with IDs: [NSManagedObjectID]) {
        do {
            let manualGlucoseObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? GlucoseStored
            }
            manualGlucoseFromPersistence = manualGlucoseObjects
        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the manual glucose array: \(error.localizedDescription)"
            )
        }
    }

    // Setup Carbs
    private func setupCarbsArray() {
        Task {
            let ids = await self.fetchCarbs()
            await updateCarbsArray(with: ids)
        }
    }

    private func fetchCarbs() async -> [NSManagedObjectID] {
        CoreDataStack.shared.fetchEntities(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.carbsForChart,
            key: "date",
            ascending: false
        ).map(\.objectID)
    }

    @MainActor private func updateCarbsArray(with IDs: [NSManagedObjectID]) {
        do {
            let carbObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? CarbEntryStored
            }
            carbsFromPersistence = carbObjects
        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the carbs array: \(error.localizedDescription)"
            )
        }
    }

    // Setup FPUs
    private func setupFPUsArray() {
        Task {
            let ids = await self.fetchFPUs()
            await updateFPUsArray(with: ids)
        }
    }

    private func fetchFPUs() async -> [NSManagedObjectID] {
        CoreDataStack.shared.fetchEntities(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.fpusForChart,
            key: "date",
            ascending: false
        ).map(\.objectID)
    }

    @MainActor private func updateFPUsArray(with IDs: [NSManagedObjectID]) {
        do {
            let fpuObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? CarbEntryStored
            }
            fpusFromPersistence = fpuObjects
        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the fpus array: \(error.localizedDescription)"
            )
        }
    }

    // Setup Determinations
    private func setupDeterminationsArray() {
        Task {
            let enactedObjectIDs = await fetchDeterminations(predicate: NSPredicate.enactedDetermination)
            let enactedAndNonEnactedObjectIDs = await fetchDeterminations(
                predicate: NSPredicate
                    .predicateFor30MinAgoForDetermination
            )

            await updateDeterminationsArray(with: enactedObjectIDs, keyPath: \.determinationsFromPersistence)
            await updateDeterminationsArray(with: enactedAndNonEnactedObjectIDs, keyPath: \.enactedAndNonEnactedDeterminations)
        }
    }

    private func fetchDeterminations(predicate: NSPredicate) async -> [NSManagedObjectID] {
        CoreDataStack.shared.fetchEntities(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: predicate,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1
        ).map(\.objectID)
    }

    @MainActor private func updateDeterminationsArray(
        with IDs: [NSManagedObjectID],
        keyPath: ReferenceWritableKeyPath<Home.StateModel, [OrefDetermination]>
    ) {
        do {
            let determinationObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OrefDetermination
            }
            self[keyPath: keyPath] = determinationObjects
        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the determinations array: \(error.localizedDescription)"
            )
        }
    }

    // Setup Insulin
    private func setupInsulinArray() {
        Task {
            let ids = await self.fetchInsulin()
            await updateInsulinArray(with: ids)
        }
    }

    private func fetchInsulin() async -> [NSManagedObjectID] {
        CoreDataStack.shared.fetchEntities(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: true
        ).map(\.objectID)
    }

    @MainActor private func updateInsulinArray(with IDs: [NSManagedObjectID]) {
        do {
            let insulinObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? PumpEventStored
            }
            insulinFromPersistence = insulinObjects

            // filter tempbasals
            manualTempBasal = apsManager.isManualTempBasal
            tempBasals = insulinFromPersistence.filter({ $0.tempBasal != nil })

            // suspension and resume events
            suspensions = insulinFromPersistence
                .filter({ $0.type == EventType.pumpSuspend.rawValue || $0.type == EventType.pumpResume.rawValue })
            let lastSuspension = suspensions.last

            pumpSuspended = tempBasals.last?.timestamp ?? Date() > lastSuspension?.timestamp ?? .distantPast && lastSuspension?
                .type == EventType.pumpSuspend
                .rawValue

        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the insulin array: \(error.localizedDescription)"
            )
        }
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
        CoreDataStack.shared.fetchEntities(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.lastPumpBolus,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        ).map(\.objectID).first
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
            await updateBatteryArray(with: ids)
        }
    }

    private func fetchBattery() async -> [NSManagedObjectID] {
        CoreDataStack.shared.fetchEntities(
            ofType: OpenAPS_Battery.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "date",
            ascending: false
        ).map(\.objectID)
    }

    @MainActor private func updateBatteryArray(with IDs: [NSManagedObjectID]) {
        do {
            let batteryObjects = try IDs.compactMap { id in
                try viewContext.existingObject(with: id) as? OpenAPS_Battery
            }
            batteryFromPersistence = batteryObjects
        } catch {
            debugPrint(
                "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the battery array: \(error.localizedDescription)"
            )
        }
    }
}
