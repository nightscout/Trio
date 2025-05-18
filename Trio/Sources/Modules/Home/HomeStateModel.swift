import CGMBLEKitUI
import Combine
import CoreData
import Foundation
import LoopKitUI
import Observation
import SwiftDate
import SwiftUI

extension Home {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var apsManager: APSManager!
        @ObservationIgnored @Injected() var pluginCGMManager: PluginManager!
        @ObservationIgnored @Injected() var fetchGlucoseManager: FetchGlucoseManager!
        @ObservationIgnored @Injected() var nightscoutManager: NightscoutManager!
        @ObservationIgnored @Injected() var determinationStorage: DeterminationStorage!
        @ObservationIgnored @Injected() var glucoseStorage: GlucoseStorage!
        @ObservationIgnored @Injected() var carbsStorage: CarbsStorage!
        @ObservationIgnored @Injected() var tempTargetStorage: TempTargetsStorage!
        @ObservationIgnored @Injected() var overrideStorage: OverrideStorage!
        @ObservationIgnored @Injected() var bluetoothManager: BluetoothStateManager!

        var cgmStateModel: CGMSettings.StateModel {
            CGMSettings.StateModel.shared
        }

        private let timer = DispatchTimer(timeInterval: 5)
        private(set) var filteredHours = 24
        var startMarker = Date(timeIntervalSinceNow: TimeInterval(hours: -24))
        var endMarker = Date(timeIntervalSinceNow: TimeInterval(hours: 3))
        var manualGlucose: [BloodGlucose] = []
        var uploadStats = false
        var recentGlucose: BloodGlucose?
        var maxBasal: Decimal = 2
        var basalProfile: [BasalProfileEntry] = []
        var bgTargets = BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
            ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        var targetProfiles: [TargetProfile] = []
        var timerDate = Date()
        var closedLoop = false
        var pumpSuspended = false
        var isLooping = false
        var statusTitle = ""
        var lastLoopDate: Date = .distantPast
        var battery: Battery?
        var reservoir: Decimal?
        var pumpName = ""
        var pumpExpiresAtDate: Date?
        var highTTraisesSens: Bool = false
        var lowTTlowersSens: Bool = false
        var isExerciseModeActive: Bool = false
        var settingHalfBasalTarget: Decimal = 160
        var percentage: Int = 100
        var shouldDisplayPumpSetupSheet = false
        var shouldDisplayCGMSetupSheet = false
        var errorMessage: String?
        var errorDate: Date?
        var bolusProgress: Decimal?
        var eventualBG: Int?
        var allowManualTemp = false
        var units: GlucoseUnits = .mgdL
        var pumpDisplayState: PumpDisplayState?
        var alarm: GlucoseAlarm?
        var manualTempBasal = false
        var isSmoothingEnabled = false
        var maxIOB: Decimal = 0.0
        var autosensMax: Decimal = 1.2
        var lowGlucose: Decimal = 70
        var highGlucose: Decimal = 180
        var currentGlucoseTarget: Decimal = 100
        var glucoseColorScheme: GlucoseColorScheme = .staticColor
        var eA1cDisplayUnit: EstimatedA1cDisplayUnit = .percent
        var displayXgridLines: Bool = false
        var displayYgridLines: Bool = false
        var thresholdLines: Bool = false
        var hours: Int16 = 6
        var totalBolus: Decimal = 0
        var isLoopStatusPresented: Bool = false
        var isLegendPresented: Bool = false
        var roundedTotalBolus: String = ""
        var selectedTab: Int = 0
        var waitForSuggestion: Bool = false
        var glucoseFromPersistence: [GlucoseStored] = []
        var latestTwoGlucoseValues: [GlucoseStored] = []
        var carbsFromPersistence: [CarbEntryStored] = []
        var fpusFromPersistence: [CarbEntryStored] = []
        var determinationsFromPersistence: [OrefDetermination] = []
        var enactedAndNonEnactedDeterminations: [OrefDetermination] = []
        var fetchedTDDs: [TDD] = []
        var insulinFromPersistence: [PumpEventStored] = []
        var tempBasals: [PumpEventStored] = []
        var suspensions: [PumpEventStored] = []
        var batteryFromPersistence: [OpenAPS_Battery] = []
        var lastPumpBolus: PumpEventStored?
        var overrides: [OverrideStored] = []
        var overrideRunStored: [OverrideRunStored] = []
        var tempTargetStored: [TempTargetStored] = []
        var tempTargetRunStored: [TempTargetRunStored] = []
        var isOverrideCancelled: Bool = false
        var preprocessedData: [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)] = []
        var pumpStatusHighlightMessage: String?
        var pumpStatusBadgeImage: UIImage?
        var pumpStatusBadgeColor: Color?
        var cgmAvailable: Bool = false
        var listOfCGM: [CGMModel] = []
        var cgmCurrent = cgmDefaultModel
        var shouldRunDeleteOnSettingsChange = true

        var showCarbsRequiredBadge: Bool = true
        private(set) var setupPumpType: PumpConfig.PumpType = .minimed
        var minForecast: [Int] = []
        var maxForecast: [Int] = []
        var minCount: Int = 12 // count of Forecasts drawn in 5 min distances, i.e. 12 means a min of 1 hour
        var forecastDisplayType: ForecastDisplayType = .cone

        var minYAxisValue: Decimal = 39
        var maxYAxisValue: Decimal = 200

        var minValueCobChart: Decimal = 0
        var maxValueCobChart: Decimal = 20

        var minValueIobChart: Decimal = 0
        var maxValueIobChart: Decimal = 5

        let taskContext = CoreDataStack.shared.newTaskContext()
        let glucoseFetchContext = CoreDataStack.shared.newTaskContext()
        let carbsFetchContext = CoreDataStack.shared.newTaskContext()
        let fpuFetchContext = CoreDataStack.shared.newTaskContext()
        let determinationFetchContext = CoreDataStack.shared.newTaskContext()
        let tddFetchContext = CoreDataStack.shared.newTaskContext()
        let pumpHistoryFetchContext = CoreDataStack.shared.newTaskContext()
        let overrideFetchContext = CoreDataStack.shared.newTaskContext()
        let tempTargetFetchContext = CoreDataStack.shared.newTaskContext()
        let batteryFetchContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        // Queue for handling Core Data change notifications
        private let queue = DispatchQueue(label: "HomeStateModel.queue", qos: .userInitiated)
        private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
        private var subscriptions = Set<AnyCancellable>()

        typealias PumpEvent = PumpEventStored.EventType

        override init() {
            super.init()
        }

        override func subscribe() {
            coreDataPublisher =
                changedObjectsOnManagedObjectContextDidSavePublisher()
                    .receive(on: queue)
                    .share()
                    .eraseToAnyPublisher()

            registerSubscribers()
            registerHandlers()

            // Parallelize Setup functions
            setupHomeViewConcurrently()
        }

        private func setupHomeViewConcurrently() {
            Task {
                // We need to initialize settings and observers first
                await self.setupSettings()
                await self.setupPumpSettings()
                await self.setupCGMSettings()
                self.registerObservers()

                // The rest can be initialized concurrently
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        self.setupGlucoseArray()
                    }
                    group.addTask {
                        self.setupCarbsArray()
                    }
                    group.addTask {
                        self.setupFPUsArray()
                    }
                    group.addTask {
                        self.setupDeterminationsArray()
                    }
                    group.addTask {
                        self.setupTDDArray()
                    }
                    group.addTask {
                        self.setupInsulinArray()
                    }
                    group.addTask {
                        self.setupLastBolus()
                    }
                    group.addTask {
                        self.setupBatteryArray()
                    }
                    group.addTask {
                        await self.setupBasalProfile()
                    }
                    group.addTask {
                        await self.setupGlucoseTargets()
                    }
                    group.addTask {
                        self.setupReservoir()
                    }
                    group.addTask {
                        self.setupOverrides()
                    }
                    group.addTask {
                        self.setupOverrideRunStored()
                    }
                    group.addTask {
                        self.setupTempTargetsStored()
                    }
                    group.addTask {
                        self.setupTempTargetsRunStored()
                    }
                }
            }
        }

        // These combine subscribers are only necessary due to the batch inserts of glucose/FPUs which do not trigger a ManagedObjectContext change notification
        private func registerSubscribers() {
            glucoseStorage.updatePublisher
                .receive(on: queue)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.setupGlucoseArray()
                }
                .store(in: &subscriptions)

            carbsStorage.updatePublisher
                .receive(on: queue)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.setupFPUsArray()
                }
                .store(in: &subscriptions)
        }

        private func registerHandlers() {
            coreDataPublisher?.filteredByEntityName("OrefDetermination").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupDeterminationsArray()
            }.store(in: &subscriptions)

            coreDataPublisher?.filteredByEntityName("TDDStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupTDDArray()
            }.store(in: &subscriptions)

            coreDataPublisher?.filteredByEntityName("GlucoseStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupGlucoseArray()
            }.store(in: &subscriptions)

            coreDataPublisher?.filteredByEntityName("CarbEntryStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupCarbsArray()
            }.store(in: &subscriptions)

            coreDataPublisher?.filteredByEntityName("PumpEventStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupInsulinArray()
                self.setupLastBolus()
                self.displayPumpStatusHighlightMessage()
                self.displayPumpStatusBadge()
            }.store(in: &subscriptions)

            coreDataPublisher?.filteredByEntityName("OpenAPS_Battery").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupBatteryArray()
            }.store(in: &subscriptions)

            coreDataPublisher?.filteredByEntityName("OverrideStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupOverrides()
            }.store(in: &subscriptions)

            coreDataPublisher?.filteredByEntityName("OverrideRunStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupOverrideRunStored()
            }.store(in: &subscriptions)

            coreDataPublisher?.filteredByEntityName("TempTargetStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupTempTargetsStored()
            }.store(in: &subscriptions)

            coreDataPublisher?.filteredByEntityName("TempTargetRunStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupTempTargetsRunStored()
            }.store(in: &subscriptions)
        }

        private func registerObservers() {
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PreferencesObserver.self, observer: self)
            broadcaster.register(PumpSettingsObserver.self, observer: self)
            broadcaster.register(BasalProfileObserver.self, observer: self)
            broadcaster.register(BGTargetsObserver.self, observer: self)
            broadcaster.register(PumpReservoirObserver.self, observer: self)
            broadcaster.register(PumpDeactivatedObserver.self, observer: self)

            timer.eventHandler = {
                DispatchQueue.main.async { [weak self] in
                    self?.timerDate = Date()
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
                        info(.default, String(describing: error))
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
                        self.shouldDisplayPumpSetupSheet = false
                    } else {
                        self.setupReservoir()
                        self.displayPumpStatusHighlightMessage()
                        self.displayPumpStatusBadge()
                        self.setupBatteryArray()
                    }
                }
                .store(in: &lifetime)
        }

        private enum SettingType {
            case basal
            case carbRatio
            case bgTarget
            case isf
        }

        @MainActor private func setupSettings() async {
            units = settingsManager.settings.units
            allowManualTemp = !settingsManager.settings.closedLoop
            closedLoop = settingsManager.settings.closedLoop
            lastLoopDate = apsManager.lastLoopDate
            alarm = provider.glucoseStorage.alarm
            manualTempBasal = apsManager.isManualTempBasal
            isSmoothingEnabled = settingsManager.settings.smoothGlucose
            glucoseColorScheme = settingsManager.settings.glucoseColorScheme
            autosensMax = settingsManager.preferences.autosensMax
            lowGlucose = settingsManager.settings.low
            highGlucose = settingsManager.settings.high
            eA1cDisplayUnit = settingsManager.settings.eA1cDisplayUnit
            displayXgridLines = settingsManager.settings.xGridLines
            displayYgridLines = settingsManager.settings.yGridLines
            thresholdLines = settingsManager.settings.rulerMarks
            showCarbsRequiredBadge = settingsManager.settings.showCarbsRequiredBadge
            forecastDisplayType = settingsManager.settings.forecastDisplayType
            isExerciseModeActive = settingsManager.preferences.exerciseMode
            highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
            lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
            settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            maxIOB = settingsManager.preferences.maxIOB
        }

        @MainActor private func setupCGMSettings() async {
            cgmAvailable = fetchGlucoseManager.cgmGlucoseSourceType != CGMType.none

            listOfCGM = (
                CGMType.allCases.filter { $0 != CGMType.plugin }.map {
                    CGMModel(id: $0.id, type: $0, displayName: $0.displayName, subtitle: $0.subtitle)
                } +
                    pluginCGMManager.availableCGMManagers.map {
                        CGMModel(
                            id: $0.identifier,
                            type: CGMType.plugin,
                            displayName: $0.localizedTitle,
                            subtitle: $0.localizedTitle
                        )
                    }
            ).sorted(by: { lhs, rhs in
                if lhs.displayName == "None" {
                    return true
                } else if rhs.displayName == "None" {
                    return false
                } else {
                    return lhs.displayName < rhs.displayName
                }
            })

            switch settingsManager.settings.cgm {
            case .plugin:
                if let cgmPluginInfo = listOfCGM.first(where: { $0.id == settingsManager.settings.cgmPluginIdentifier }) {
                    cgmCurrent = CGMModel(
                        id: settingsManager.settings.cgmPluginIdentifier,
                        type: .plugin,
                        displayName: cgmPluginInfo.displayName,
                        subtitle: cgmPluginInfo.subtitle
                    )
                } else {
                    // no more type of plugin available - fallback to default
                    cgmCurrent = cgmDefaultModel
                }
            default:
                cgmCurrent = CGMModel(
                    id: settingsManager.settings.cgm.id,
                    type: settingsManager.settings.cgm,
                    displayName: settingsManager.settings.cgm.displayName,
                    subtitle: settingsManager.settings.cgm.subtitle
                )
            }
        }

        func addPump(_ type: PumpConfig.PumpType) {
            setupPumpType = type
            shouldDisplayPumpSetupSheet = true
        }

        func addCGM(cgm: CGMModel) {
            cgmCurrent = cgm
            switch cgmCurrent.type {
            case .plugin:
                shouldDisplayCGMSetupSheet = true
            default:
                shouldDisplayCGMSetupSheet = true
                settingsManager.settings.cgm = cgmCurrent.type
                settingsManager.settings.cgmPluginIdentifier = ""
                fetchGlucoseManager.updateGlucoseSource(cgmGlucoseSourceType: cgmCurrent.type, cgmGlucosePluginId: cgmCurrent.id)
                broadcaster.notify(GlucoseObserver.self, on: .main) {
                    $0.glucoseDidUpdate([])
                }
            }
        }

        func deleteCGM() {
            fetchGlucoseManager.performOnCGMManagerQueue {
                // Call plugin functionality on the manager queue (or at least attempt to)
                Task {
                    await self.fetchGlucoseManager?.deleteGlucoseSource()

                    // UI updates go back to Main
                    await MainActor.run {
                        self.shouldDisplayCGMSetupSheet = false
                        self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                            $0.glucoseDidUpdate([])
                        }
                    }
                }
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

        private func displayPumpStatusBadge(_ didDeactivate: Bool = false) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let statusBadge = self.provider.deviceManager.pumpManager?.pumpStatusBadge,
                   let image = statusBadge.image, !didDeactivate
                {
                    pumpStatusBadgeImage = image
                    pumpStatusBadgeColor = statusBadge.state == .critical ? .critical : .warning

                } else {
                    pumpStatusBadgeImage = nil
                    pumpStatusBadgeColor = nil
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
                await apsManager.cancelBolus(nil)

                // perform determine basal sync, otherwise you have could end up with too much iob when opening the calculator again
                try await apsManager.determineBasalSync()
            }
        }

        private func setupPumpSettings() async {
            let maxBasal = await provider.pumpSettings().maxBasal
            await MainActor.run {
                self.maxBasal = maxBasal
            }
        }

        private func setupBasalProfile() async {
            let basalProfile = await provider.getBasalProfile()
            await MainActor.run {
                self.basalProfile = basalProfile
            }
        }

        private func setupGlucoseTargets() async {
            let bgTargets = await provider.getBGTargets()
            let targetProfiles = processFetchedTargets(bgTargets, startMarker: startMarker)
            await MainActor.run {
                self.bgTargets = bgTargets
                self.targetProfiles = targetProfiles
            }
        }

        private func setupReservoir() {
            Task {
                let reservoir = await provider.pumpReservoir()
                await MainActor.run {
                    self.reservoir = reservoir
                }
            }
        }

        private func getCurrentGlucoseTarget() async {
            let now = Date()
            let calendar = Calendar.current

            let entries: [(start: String, value: Decimal)] = bgTargets.targets.map { ($0.start, $0.low) }

            for (index, entry) in entries.enumerated() {
                guard let entryTime = TherapySettingsUtil.parseTime(entry.start) else {
                    debug(.default, "Invalid entry start time: \(entry.start)")
                    continue
                }

                let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
                let entryStartTime = calendar.date(
                    bySettingHour: entryComponents.hour!,
                    minute: entryComponents.minute!,
                    second: entryComponents.second!,
                    of: now
                )!

                let entryEndTime: Date
                if index < entries.count - 1,
                   let nextEntryTime = TherapySettingsUtil.parseTime(entries[index + 1].start)
                {
                    let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                    entryEndTime = calendar.date(
                        bySettingHour: nextEntryComponents.hour!,
                        minute: nextEntryComponents.minute!,
                        second: nextEntryComponents.second!,
                        of: now
                    )!
                } else {
                    entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
                }

                if now >= entryStartTime, now < entryEndTime {
                    await MainActor.run {
                        currentGlucoseTarget = entry.value
                    }
                    return
                }
            }
        }
    }
}

extension Home.StateModel:
    DeterminationObserver,
    SettingsObserver,
    PreferencesObserver,
    PumpSettingsObserver,
    BasalProfileObserver,
    BGTargetsObserver,
    PumpReservoirObserver,
    PumpDeactivatedObserver
{
    func determinationDidUpdate(_: Determination) {
        waitForSuggestion = false
    }

    func settingsDidChange(_ settings: TrioSettings) {
        allowManualTemp = !settings.closedLoop
        closedLoop = settingsManager.settings.closedLoop
        units = settingsManager.settings.units
        manualTempBasal = apsManager.isManualTempBasal
        isSmoothingEnabled = settingsManager.settings.smoothGlucose
        lowGlucose = settingsManager.settings.low
        highGlucose = settingsManager.settings.high
        Task {
            await getCurrentGlucoseTarget()
            await setupGlucoseTargets()
        }
        eA1cDisplayUnit = settingsManager.settings.eA1cDisplayUnit
        glucoseColorScheme = settingsManager.settings.glucoseColorScheme
        displayXgridLines = settingsManager.settings.xGridLines
        displayYgridLines = settingsManager.settings.yGridLines
        thresholdLines = settingsManager.settings.rulerMarks
        showCarbsRequiredBadge = settingsManager.settings.showCarbsRequiredBadge
        forecastDisplayType = settingsManager.settings.forecastDisplayType
        cgmAvailable = (fetchGlucoseManager.cgmGlucoseSourceType != CGMType.none)
        displayPumpStatusHighlightMessage()
        displayPumpStatusBadge()
        setupBatteryArray()
        Task {
            await setupCGMSettings()
        }
        if settingsManager.settings.cgm == .none, shouldRunDeleteOnSettingsChange {
            shouldRunDeleteOnSettingsChange = false
            cgmCurrent = cgmDefaultModel
            DispatchQueue.main.async {
                self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                    $0.glucoseDidUpdate([])
                }
            }
        } else {
            shouldRunDeleteOnSettingsChange = true
        }
    }

    func preferencesDidChange(_: Preferences) {
        autosensMax = settingsManager.preferences.autosensMax
        settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
        highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
        isExerciseModeActive = settingsManager.preferences.exerciseMode
        lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
        maxIOB = settingsManager.preferences.maxIOB
    }

    func pumpSettingsDidChange(_: PumpSettings) {
        Task {
            await setupPumpSettings()
            setupBatteryArray()
        }
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) {
        Task {
            await setupBasalProfile()
        }
    }

    func bgTargetsDidChange(_: BGTargets) {
        Task {
            await setupGlucoseTargets()
        }
    }

    func pumpReservoirDidChange(_: Decimal) {
        setupReservoir()
        displayPumpStatusHighlightMessage()
        displayPumpStatusBadge()
    }

    func pumpDeactivatedDidChange() {
        displayPumpStatusHighlightMessage(true)
        displayPumpStatusBadge(true)
        batteryFromPersistence = []
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
        // nothing to do
    }
}
