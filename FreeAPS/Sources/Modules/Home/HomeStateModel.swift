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
        @Injected() var tempTargetStorage: TempTargetsStorage!
        @Injected() var carbsStorage: CarbsStorage!
        private let timer = DispatchTimer(timeInterval: 5)
        private(set) var filteredHours = 24
        @Published var manualGlucose: [BloodGlucose] = []
        @Published var uploadStats = false
        @Published var recentGlucose: BloodGlucose?
        @Published var maxBasal: Decimal = 2
        @Published var autotunedBasalProfile: [BasalProfileEntry] = []
        @Published var basalProfile: [BasalProfileEntry] = []
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
        @Published var setupPump = false
        @Published var errorMessage: String? = nil
        @Published var errorDate: Date? = nil
        @Published var bolusProgress: Decimal?
        @Published var eventualBG: Int?
        @Published var allowManualTemp = false
        @Published var units: GlucoseUnits = .mgdL
        @Published var pumpDisplayState: PumpDisplayState?
        @Published var alarm: GlucoseAlarm?
        @Published var manualTempBasal = false
        @Published var isSmoothingEnabled = false
        @Published var maxValue: Decimal = 1.2
        @Published var lowGlucose: Decimal = 70
        @Published var highGlucose: Decimal = 180
        @Published var currentGlucoseTarget: Decimal = 100
        @Published var overrideUnit: Bool = false
        @Published var glucoseColorScheme: GlucoseColorScheme = .staticColor
        @Published var displayXgridLines: Bool = false
        @Published var displayYgridLines: Bool = false
        @Published var thresholdLines: Bool = false
        @Published var timeZone: TimeZone?
        @Published var hours: Int16 = 6
        @Published var totalBolus: Decimal = 0
        @Published var isStatusPopupPresented: Bool = false
        @Published var isLegendPresented: Bool = false
        @Published var legendSheetDetent = PresentationDetent.large
        @Published var totalInsulinDisplayType: TotalInsulinDisplayType = .totalDailyDose
        @Published var roundedTotalBolus: String = ""
        @Published var selectedTab: Int = 0
        @Published var waitForSuggestion: Bool = false
        @Published var glucoseFromPersistence: [GlucoseStored] = []
        @Published var latestTwoGlucoseValues: [GlucoseStored] = []
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
        @Published var tempTargetStored: [TempTargetStored] = []
        @Published var tempTargetRunStored: [TempTargetRunStored] = []
        @Published var isOverrideCancelled: Bool = false
        @Published var preprocessedData: [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)] = []
        @Published var pumpStatusHighlightMessage: String? = nil
        @Published var cgmAvailable: Bool = false
        @Published var showCarbsRequiredBadge: Bool = true
        private(set) var setupPumpType: PumpConfig.PumpType = .minimed
        @Published var currentBGTarget: Decimal = 0

        @Published var minForecast: [Int] = []
        @Published var maxForecast: [Int] = []
        @Published var minCount: Int = 12 // count of Forecasts drawn in 5 min distances, i.e. 12 means a min of 1 hour
        @Published var forecastDisplayType: ForecastDisplayType = .cone

        @Published var minYAxisValue: Decimal = 39
        @Published var maxYAxisValue: Decimal = 300

        @Published var minValueCobChart: Decimal = 0
        @Published var maxValueCobChart: Decimal = 20

        @Published var minValueIobChart: Decimal = 0
        @Published var maxValueIobChart: Decimal = 5

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
                    group.addTask {
                        await self.getCurrentBGTarget()
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
        }

        private func registerObservers() {
            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
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

        private func getCurrentBGTarget() async {
            let now = Date()
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            dateFormatter.timeZone = TimeZone.current

            let entries: [(start: String, value: Decimal)]

            let bgTargets = await provider.getBGTarget()
            entries = bgTargets.targets.map { ($0.start, $0.low) }

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
                        currentBGTarget = entry.value
                    }
                    return
                }
            }
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
            lowGlucose = units == .mgdL ? settingsManager.settings.low : settingsManager.settings.low.asMmolL
            highGlucose = units == .mgdL ? settingsManager.settings.high : settingsManager.settings.high.asMmolL
            overrideUnit = settingsManager.settings.overrideHbA1cUnit
            displayXgridLines = settingsManager.settings.xGridLines
            displayYgridLines = settingsManager.settings.yGridLines
            thresholdLines = settingsManager.settings.rulerMarks
            totalInsulinDisplayType = settingsManager.settings.totalInsulinDisplayType
            cgmAvailable = fetchGlucoseManager.cgmGlucoseSourceType != CGMType.none
            showCarbsRequiredBadge = settingsManager.settings.showCarbsRequiredBadge
            forecastDisplayType = settingsManager.settings.forecastDisplayType
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
            dateFormatter.dateFormat = "HH:mm:ss"
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
                        currentGlucoseTarget = units == .mgdL ? entry.value : entry.value.asMmolL
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

    func settingsDidChange(_ settings: FreeAPSSettings) {
        allowManualTemp = !settings.closedLoop
        closedLoop = settingsManager.settings.closedLoop
        units = settingsManager.settings.units
        manualTempBasal = apsManager.isManualTempBasal
        isSmoothingEnabled = settingsManager.settings.smoothGlucose
        lowGlucose = units == .mgdL ? settingsManager.settings.low : settingsManager.settings.low.asMmolL
        highGlucose = units == .mgdL ? settingsManager.settings.high : settingsManager.settings.high.asMmolL
        Task {
            await getCurrentGlucoseTarget()
        }
        overrideUnit = settingsManager.settings.overrideHbA1cUnit
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

        Task {
            await self.getCurrentBGTarget()
        }
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
