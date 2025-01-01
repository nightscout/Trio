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
        @ObservationIgnored @Injected() var fetchGlucoseManager: FetchGlucoseManager!
        @ObservationIgnored @Injected() var nightscoutManager: NightscoutManager!
        @ObservationIgnored @Injected() var determinationStorage: DeterminationStorage!
        @ObservationIgnored @Injected() var glucoseStorage: GlucoseStorage!
        @ObservationIgnored @Injected() var carbsStorage: CarbsStorage!
        @ObservationIgnored @Injected() var tempTargetStorage: TempTargetsStorage!
        @ObservationIgnored @Injected() var overrideStorage: OverrideStorage!
        private let timer = DispatchTimer(timeInterval: 5)
        private(set) var filteredHours = 24
        var manualGlucose: [BloodGlucose] = []
        var uploadStats = false
        var recentGlucose: BloodGlucose?
        var maxBasal: Decimal = 2
        var autotunedBasalProfile: [BasalProfileEntry] = []
        var basalProfile: [BasalProfileEntry] = []
        var tempTargets: [TempTarget] = []
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
        var tempTarget: TempTarget?
        var highTTraisesSens: Bool = false
        var lowTTlowersSens: Bool = false
        var isExerciseModeActive: Bool = false
        var settingHalfBasalTarget: Decimal = 160
        var percentage: Int = 100
        var setupPump = false
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
        var maxValue: Decimal = 1.2
        var lowGlucose: Decimal = 70
        var highGlucose: Decimal = 180
        var currentGlucoseTarget: Decimal = 100
        var glucoseColorScheme: GlucoseColorScheme = .staticColor
        var hbA1cDisplayUnit: HbA1cDisplayUnit = .percent
        var displayXgridLines: Bool = false
        var displayYgridLines: Bool = false
        var thresholdLines: Bool = false
        var timeZone: TimeZone?
        var hours: Int16 = 6
        var totalBolus: Decimal = 0
        var isStatusPopupPresented: Bool = false
        var isLegendPresented: Bool = false
        var totalInsulinDisplayType: TotalInsulinDisplayType = .totalDailyDose
        var roundedTotalBolus: String = ""
        var selectedTab: Int = 0
        var waitForSuggestion: Bool = false
        var glucoseFromPersistence: [GlucoseStored] = []
        var latestTwoGlucoseValues: [GlucoseStored] = []
        var carbsFromPersistence: [CarbEntryStored] = []
        var fpusFromPersistence: [CarbEntryStored] = []
        var determinationsFromPersistence: [OrefDetermination] = []
        var enactedAndNonEnactedDeterminations: [OrefDetermination] = []
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
        var cgmAvailable: Bool = false
        var showCarbsRequiredBadge: Bool = true
        private(set) var setupPumpType: PumpConfig.PumpType = .minimed
        var minForecast: [Int] = []
        var maxForecast: [Int] = []
        var minCount: Int = 12 // count of Forecasts drawn in 5 min distances, i.e. 12 means a min of 1 hour
        var forecastDisplayType: ForecastDisplayType = .cone

        var minYAxisValue: Decimal = 39
        var maxYAxisValue: Decimal = 300

        var minValueCobChart: Decimal = 0
        var maxValueCobChart: Decimal = 20

        var minValueIobChart: Decimal = 0
        var maxValueIobChart: Decimal = 5

        let taskContext = CoreDataStack.shared.newTaskContext()
        let glucoseFetchContext = CoreDataStack.shared.newTaskContext()
        let carbsFetchContext = CoreDataStack.shared.newTaskContext()
        let fpuFetchContext = CoreDataStack.shared.newTaskContext()
        let determinationFetchContext = CoreDataStack.shared.newTaskContext()
        let pumpHistoryFetchContext = CoreDataStack.shared.newTaskContext()
        let overrideFetchContext = CoreDataStack.shared.newTaskContext()
        let tempTargetFetchContext = CoreDataStack.shared.newTaskContext()
        let batteryFetchContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
        private var subscriptions = Set<AnyCancellable>()

        typealias PumpEvent = PumpEventStored.EventType

        override func subscribe() {
            coreDataPublisher =
                changedObjectsOnManagedObjectContextDidSavePublisher()
                    .receive(on: DispatchQueue.global(qos: .background))
                    .share()
                    .eraseToAnyPublisher()

            registerSubscribers()
            registerHandlers()

            // Parallelize Setup functions
            setupHomeViewConcurrently()
        }

        private func setupHomeViewConcurrently() {
            Task {
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
                        self.setupInsulinArray()
                    }
                    group.addTask {
                        self.setupLastBolus()
                    }
                    group.addTask {
                        self.setupBatteryArray()
                    }
                    group.addTask {
                        self.setupPumpSettings()
                    }
                    group.addTask {
                        self.setupBasalProfile()
                    }
                    group.addTask {
                        self.setupReservoir()
                    }
                    group.addTask {
                        self.setupCurrentPumpTimezone()
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
                    group.addTask {
                        await self.setupSettings()
                    }
                    group.addTask {
                        self.registerObservers()
                    }
                }
            }
        }

        // These combine subscribers are only necessary due to the batch inserts of glucose/FPUs which do not trigger a ManagedObjectContext change notification
        private func registerSubscribers() {
            glucoseStorage.updatePublisher
                .receive(on: DispatchQueue.global(qos: .background))
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.setupGlucoseArray()
                }
                .store(in: &subscriptions)

            carbsStorage.updatePublisher
                .receive(on: DispatchQueue.global(qos: .background))
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.setupFPUsArray()
                }
                .store(in: &subscriptions)
        }

        private func registerHandlers() {
            coreDataPublisher?.filterByEntityName("OrefDetermination").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupDeterminationsArray()
            }.store(in: &subscriptions)

            coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupGlucoseArray()
            }.store(in: &subscriptions)

            coreDataPublisher?.filterByEntityName("CarbEntryStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupCarbsArray()
            }.store(in: &subscriptions)

            coreDataPublisher?.filterByEntityName("PumpEventStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupInsulinArray()
                self.setupLastBolus()
                self.displayPumpStatusHighlightMessage()
            }.store(in: &subscriptions)

            coreDataPublisher?.filterByEntityName("OpenAPS_Battery").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupBatteryArray()
            }.store(in: &subscriptions)

            coreDataPublisher?.filterByEntityName("OverrideStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupOverrides()
            }.store(in: &subscriptions)

            coreDataPublisher?.filterByEntityName("OverrideRunStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupOverrideRunStored()
            }.store(in: &subscriptions)

            coreDataPublisher?.filterByEntityName("TempTargetStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupTempTargetsStored()
            }.store(in: &subscriptions)

            coreDataPublisher?.filterByEntityName("TempTargetRunStored").sink { [weak self] _ in
                guard let self = self else { return }
                self.setupTempTargetsRunStored()
            }.store(in: &subscriptions)
        }

        private func registerObservers() {
            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PreferencesObserver.self, observer: self)
            broadcaster.register(PumpSettingsObserver.self, observer: self)
            broadcaster.register(BasalProfileObserver.self, observer: self)
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
            maxValue = settingsManager.preferences.autosensMax
            lowGlucose = settingsManager.settings.low
            highGlucose = settingsManager.settings.high
            hbA1cDisplayUnit = settingsManager.settings.hbA1cDisplayUnit
            displayXgridLines = settingsManager.settings.xGridLines
            displayYgridLines = settingsManager.settings.yGridLines
            thresholdLines = settingsManager.settings.rulerMarks
            totalInsulinDisplayType = settingsManager.settings.totalInsulinDisplayType
            cgmAvailable = fetchGlucoseManager.cgmGlucoseSourceType != CGMType.none
            showCarbsRequiredBadge = settingsManager.settings.showCarbsRequiredBadge
            forecastDisplayType = settingsManager.settings.forecastDisplayType
            isExerciseModeActive = settingsManager.preferences.exerciseMode
            highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
            lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
            settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            maxValue = settingsManager.preferences.autosensMax
        }

        func addPump(_ type: PumpConfig.PumpType) {
            setupPumpType = type
            setupPump = true
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

        private func setupReservoir() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.reservoir = self.provider.pumpReservoir()
            }
        }

        private func setupCurrentPumpTimezone() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.timeZone = self.provider.pumpTimeZone()
            }
        }

        private func getCurrentGlucoseTarget() async {
            let now = Date()
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm"
            dateFormatter.timeZone = TimeZone.current

            let bgTargets = await provider.getBGTarget()
            let entries: [(start: String, value: Decimal)] = bgTargets.targets.map { ($0.start, $0.low) }

            for (index, entry) in entries.enumerated() {
                guard let entryTime = dateFormatter.date(from: entry.start) else {
                    print("Invalid entry start time: \(entry.start)")
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
                   let nextEntryTime = dateFormatter.date(from: entries[index + 1].start)
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

        func openCGM() {
            router.mainSecondaryModalView.send(router.view(for: .cgmDirect))
        }
    }
}

extension Home.StateModel:
    GlucoseObserver,
    DeterminationObserver,
    SettingsObserver,
    PreferencesObserver,
    PumpSettingsObserver,
    BasalProfileObserver,
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
        }
        hbA1cDisplayUnit = settingsManager.settings.hbA1cDisplayUnit
        glucoseColorScheme = settingsManager.settings.glucoseColorScheme
        displayXgridLines = settingsManager.settings.xGridLines
        displayYgridLines = settingsManager.settings.yGridLines
        thresholdLines = settingsManager.settings.rulerMarks
        totalInsulinDisplayType = settingsManager.settings.totalInsulinDisplayType
        showCarbsRequiredBadge = settingsManager.settings.showCarbsRequiredBadge
        forecastDisplayType = settingsManager.settings.forecastDisplayType
        cgmAvailable = (fetchGlucoseManager.cgmGlucoseSourceType != CGMType.none)
        displayPumpStatusHighlightMessage()
        setupBatteryArray()
    }

    func preferencesDidChange(_: Preferences) {
        maxValue = settingsManager.preferences.autosensMax
        settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
        highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
        isExerciseModeActive = settingsManager.preferences.exerciseMode
        lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
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
