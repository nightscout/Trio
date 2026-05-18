import CGMBLEKitUI
import Combine
import CoreData
import Foundation
import LoopKit
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
        @ObservationIgnored @Injected() var iobService: IOBService!

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
        var isLooping = false
        var statusTitle = ""
        var lastLoopDate: Date = .distantPast
        var battery: Battery?
        var reservoir: Decimal?
        var pumpName = ""
        var pumpExpiresAtDate: Date?
        var pumpActivatedAtDate: Date?
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
        var currentIOB: Decimal = 0.0
        var autosensMax: Decimal = 1.2
        var lowGlucose: Decimal = 70
        var highGlucose: Decimal = 180
        var currentGlucoseTarget: Decimal = 100
        var glucoseColorScheme: GlucoseColorScheme = .staticColor
        var eA1cDisplayUnit: EstimatedA1cDisplayUnit = .percent
        var displayXgridLines: Bool = false
        var displayYgridLines: Bool = false
        var thresholdLines: Bool = false
        var bolusDisplayThreshold: BolusDisplayThreshold = .allUnits
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
        var suspendAndResumeEvents: [PumpEventStored] = []
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
        var pumpInitialSettings = PumpConfig.PumpInitialSettings.default
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

        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        // MARK: - NSFetchedResultsControllers

        //
        // Each Core Data backed array on this state model is driven by an NSFetchedResultsController
        // bound to the viewContext. The controllers keep their `fetchedObjects` continuously in sync
        // with the viewContext (which in turn is fed by the persistent history merge in CoreDataStack)
        // and notify us via their delegate's `onContentChange` closure. This replaces the previous
        // hand-rolled `changedObjectsOnManagedObjectContextDidSavePublisher` + re-fetch approach.

        @ObservationIgnored let glucoseControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var glucoseController: NSFetchedResultsController<GlucoseStored> = {
            let request = NSFetchRequest<GlucoseStored>(entityName: "GlucoseStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: true)]
            request.predicate = NSPredicate.glucose
            request.fetchBatchSize = 50
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = glucoseControllerDelegate
            return controller
        }()

        @ObservationIgnored let carbsControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var carbsController: NSFetchedResultsController<CarbEntryStored> = {
            let request = NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CarbEntryStored.date, ascending: false)]
            request.predicate = NSPredicate.carbsForChart
            request.fetchBatchSize = 5
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = carbsControllerDelegate
            return controller
        }()

        @ObservationIgnored let fpuControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var fpuController: NSFetchedResultsController<CarbEntryStored> = {
            let request = NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CarbEntryStored.date, ascending: false)]
            request.predicate = NSPredicate.fpusForChart
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = fpuControllerDelegate
            return controller
        }()

        @ObservationIgnored let enactedDeterminationControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var enactedDeterminationController: NSFetchedResultsController<OrefDetermination> =
            {
                let request = NSFetchRequest<OrefDetermination>(entityName: "OrefDetermination")
                request.sortDescriptors = [NSSortDescriptor(keyPath: \OrefDetermination.deliverAt, ascending: false)]
                request.predicate = NSPredicate.enactedDetermination
                request.fetchLimit = 1
                let controller = NSFetchedResultsController(
                    fetchRequest: request,
                    managedObjectContext: viewContext,
                    sectionNameKeyPath: nil,
                    cacheName: nil
                )
                controller.delegate = enactedDeterminationControllerDelegate
                return controller
            }()

        @ObservationIgnored let determinationControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var determinationController: NSFetchedResultsController<OrefDetermination> = {
            let request = NSFetchRequest<OrefDetermination>(entityName: "OrefDetermination")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \OrefDetermination.deliverAt, ascending: false)]
            request.predicate = NSPredicate.determinationsForCobIobCharts
            request.fetchBatchSize = 50
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = determinationControllerDelegate
            return controller
        }()

        @ObservationIgnored let insulinControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var insulinController: NSFetchedResultsController<PumpEventStored> = {
            let request = NSFetchRequest<PumpEventStored>(entityName: "PumpEventStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PumpEventStored.timestamp, ascending: true)]
            request.predicate = NSPredicate.pumpHistoryLast24h
            request.fetchBatchSize = 30
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = insulinControllerDelegate
            return controller
        }()

        @ObservationIgnored let lastBolusControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var lastBolusController: NSFetchedResultsController<PumpEventStored> = {
            let request = NSFetchRequest<PumpEventStored>(entityName: "PumpEventStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PumpEventStored.timestamp, ascending: false)]
            request.predicate = NSPredicate.lastPumpBolus
            request.fetchLimit = 1
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = lastBolusControllerDelegate
            return controller
        }()

        @ObservationIgnored let overrideControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var overrideController: NSFetchedResultsController<OverrideStored> = {
            let request = NSFetchRequest<OverrideStored>(entityName: "OverrideStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \OverrideStored.date, ascending: false)]
            request.predicate = NSPredicate.lastActiveOverride
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = overrideControllerDelegate
            return controller
        }()

        @ObservationIgnored let overrideRunControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var overrideRunController: NSFetchedResultsController<OverrideRunStored> = {
            let request = NSFetchRequest<OverrideRunStored>(entityName: "OverrideRunStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \OverrideRunStored.startDate, ascending: false)]
            request.predicate = NSPredicate(format: "startDate >= %@", Date.oneDayAgo as NSDate)
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = overrideRunControllerDelegate
            return controller
        }()

        @ObservationIgnored let tempTargetControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var tempTargetController: NSFetchedResultsController<TempTargetStored> = {
            let request = NSFetchRequest<TempTargetStored>(entityName: "TempTargetStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \TempTargetStored.date, ascending: false)]
            request.predicate = NSPredicate.tempTargetsForMainChart
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = tempTargetControllerDelegate
            return controller
        }()

        @ObservationIgnored let tempTargetRunControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var tempTargetRunController: NSFetchedResultsController<TempTargetRunStored> = {
            let request = NSFetchRequest<TempTargetRunStored>(entityName: "TempTargetRunStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \TempTargetRunStored.startDate, ascending: false)]
            request.predicate = NSPredicate(format: "startDate >= %@", Date.oneDayAgo as NSDate)
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = tempTargetRunControllerDelegate
            return controller
        }()

        @ObservationIgnored let batteryControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var batteryController: NSFetchedResultsController<OpenAPS_Battery> = {
            let request = NSFetchRequest<OpenAPS_Battery>(entityName: "OpenAPS_Battery")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \OpenAPS_Battery.date, ascending: false)]
            request.predicate = NSPredicate.predicateFor30MinAgo
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = batteryControllerDelegate
            return controller
        }()

        @ObservationIgnored let tddControllerDelegate = FetchedResultsControllerDelegate()
        @ObservationIgnored private(set) lazy var tddController: NSFetchedResultsController<TDDStored> = {
            let request = NSFetchRequest<TDDStored>(entityName: "TDDStored")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \TDDStored.date, ascending: false)]
            request.predicate = NSPredicate.predicateForOneDayAgo
            request.fetchLimit = 1
            let controller = NSFetchedResultsController(
                fetchRequest: request,
                managedObjectContext: viewContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            controller.delegate = tddControllerDelegate
            return controller
        }()

        private var subscriptions = Set<AnyCancellable>()

        typealias PumpEvent = PumpEventStored.EventType

        override init() {
            super.init()
        }

        override func subscribe() {
            registerSubscribers()

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

                // Set up the NSFetchedResultsControllers. These are bound to the viewContext,
                // so `performFetch` and the initial population must run on the main actor.
                await self.setupGlucoseController()
                await self.setupCarbsController()
                await self.setupFPUController()
                await self.setupEnactedDeterminationController()
                await self.setupDeterminationController()
                await self.setupInsulinController()
                await self.setupLastBolusController()
                await self.setupOverrideController()
                await self.setupOverrideRunController()
                await self.setupTempTargetController()
                await self.setupTempTargetRunController()
                await self.setupBatteryController()
                await self.setupTDDController()

                // The rest can be initialized concurrently
                await withTaskGroup(of: Void.self) { group in
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
                        self.iobService.updateIOB()
                    }
                }
            }
        }

        private func registerSubscribers() {
            iobService.iobPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.currentIOB = self.iobService.currentIOB ?? 0
                }
                .store(in: &subscriptions)
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

            apsManager.pumpActivatedAtDate
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.pumpActivatedAtDate, on: self)
                .store(in: &lifetime)

            apsManager.lastError
                .receive(on: DispatchQueue.main)
                .map { [weak self] error in
                    self?.errorDate = error == nil ? nil : Date()
                    if let error = error {
                        info(.default, String(describing: error), notificationText: error.localizedDescription)
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
            bolusDisplayThreshold = settingsManager.settings.bolusDisplayThreshold
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
        func displayPumpStatusHighlightMessage(_ didDeactivate: Bool = false) {
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

        func displayPumpStatusBadge(_ didDeactivate: Bool = false) {
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
            let settings = await provider.pumpSettings()
            await MainActor.run {
                self.maxBasal = settings.maxBasal
                self.pumpInitialSettings.maxBasalRateUnitsPerHour = Double(settings.maxBasal)
                self.pumpInitialSettings.maxBolusUnits = Double(settings.maxBolus)
            }
        }

        private func setupBasalProfile() async {
            let basalProfile = await provider.getBasalProfile()
            await MainActor.run {
                self.basalProfile = basalProfile

                if let schedule = BasalRateSchedule(
                    dailyItems: basalProfile
                        .map { RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate)) }
                ) {
                    self.pumpInitialSettings.basalSchedule = schedule
                }
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
        bolusDisplayThreshold = settingsManager.settings.bolusDisplayThreshold
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
