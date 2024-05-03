import Combine
import CoreData
import LoopKitUI
import SwiftDate
import SwiftUI

extension Home {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var apsManager: APSManager!
        @Injected() var fetchGlucoseManager: FetchGlucoseManager!

        private let timer = DispatchTimer(timeInterval: 5)
        private(set) var filteredHours = 24
        @Published var glucose: [BloodGlucose] = []
        @Published var suggestion: Suggestion?
        @Published var uploadStats = false
        @Published var enactedSuggestion: Suggestion?
        @Published var recentGlucose: BloodGlucose?
        @Published var glucoseDelta: Int?
        @Published var tempBasals: [PumpHistoryEvent] = []
        @Published var boluses: [PumpHistoryEvent] = []
        @Published var suspensions: [PumpHistoryEvent] = []
        @Published var maxBasal: Decimal = 2
        @Published var autotunedBasalProfile: [BasalProfileEntry] = []
        @Published var basalProfile: [BasalProfileEntry] = []
        @Published var tempTargets: [TempTarget] = []
        @Published var carbs: [CarbsEntry] = []
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
        @Published var carbsRequired: Decimal?
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
        @Published var screenHours: Int = 6
        @Published var displayXgridLines: Bool = false
        @Published var displayYgridLines: Bool = false
        @Published var thresholdLines: Bool = false
        @Published var cgmAvailable: Bool = false

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() {
            setupGlucose()
            setupBasals()
            setupBoluses()
            setupSuspensions()
            setupPumpSettings()
            setupBasalProfile()
            setupTempTargets()
            setupCarbs()
            setupBattery()
            setupReservoir()

            suggestion = provider.suggestion
            uploadStats = settingsManager.settings.uploadStats
            enactedSuggestion = provider.enactedSuggestion
            units = settingsManager.settings.units
            allowManualTemp = !settingsManager.settings.closedLoop
            closedLoop = settingsManager.settings.closedLoop
            lastLoopDate = apsManager.lastLoopDate
            carbsRequired = suggestion?.carbsReq
            alarm = provider.glucoseStorage.alarm
            manualTempBasal = apsManager.isManualTempBasal
            setStatusTitle()
            setupCurrentTempTarget()
            smooth = settingsManager.settings.smoothGlucose
            maxValue = settingsManager.preferences.autosensMax
            lowGlucose = settingsManager.settings.low
            highGlucose = settingsManager.settings.high
            overrideUnit = settingsManager.settings.overrideHbA1cUnit
            screenHours = settingsManager.settings.hours
            displayXgridLines = settingsManager.settings.xGridLines
            displayYgridLines = settingsManager.settings.yGridLines
            thresholdLines = settingsManager.settings.rulerMarks

            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(SuggestionObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(PumpSettingsObserver.self, observer: self)
            broadcaster.register(BasalProfileObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(EnactedSuggestionObserver.self, observer: self)
            broadcaster.register(PumpBatteryObserver.self, observer: self)
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
                        self.setupBattery()
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

        func addCarbs() {
            showModal(for: .addCarbs)
        }

        func runLoop() {
            provider.heartbeatNow()
        }

        func cancelBolus() {
            apsManager.cancelBolus()
        }

        func cancelProfile() {
            coredataContext.perform { [self] in
                let profiles = Override(context: self.coredataContext)
                profiles.enabled = false
                profiles.date = Date()
                try? self.coredataContext.save()
            }
        }

        private func setupGlucose() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.glucose = self.provider.filteredGlucose(hours: self.filteredHours)
                self.recentGlucose = self.glucose.last
                if self.glucose.count >= 2 {
                    self.glucoseDelta = (self.recentGlucose?.glucose ?? 0) - (self.glucose[self.glucose.count - 2].glucose ?? 0)
                } else {
                    self.glucoseDelta = nil
                }
                self.alarm = self.provider.glucoseStorage.alarm
                cgmAvailable = (fetchGlucoseManager.cgmGlucoseSourceType != CGMType.none)
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

        private func setupCarbs() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.carbs = self.provider.carbs(hours: self.filteredHours)
            }
        }

        private func setStatusTitle() {
            guard let suggestion = suggestion else {
                statusTitle = "No suggestion"
                return
            }

            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            if closedLoop,
               let enactedSuggestion = enactedSuggestion,
               let timestamp = enactedSuggestion.timestamp,
               enactedSuggestion.deliverAt == suggestion.deliverAt, enactedSuggestion.recieved == true
            {
                statusTitle = NSLocalizedString("Enacted at", comment: "Headline in enacted pop up") + " " + dateFormatter
                    .string(from: timestamp)
            } else if let suggestedDate = suggestion.deliverAt {
                statusTitle = NSLocalizedString("Suggested at", comment: "Headline in suggested pop up") + " " + dateFormatter
                    .string(from: suggestedDate)
            } else {
                statusTitle = "Suggested"
            }

            eventualBG = suggestion.eventualBG
        }

        private func setupReservoir() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.reservoir = self.provider.pumpReservoir()
            }
        }

        private func setupBattery() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.battery = self.provider.pumpBattery()
            }
        }

        private func setupCurrentTempTarget() {
            tempTarget = provider.tempTarget()
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
    SuggestionObserver,
    SettingsObserver,
    PumpHistoryObserver,
    PumpSettingsObserver,
    BasalProfileObserver,
    TempTargetsObserver,
    CarbsObserver,
    EnactedSuggestionObserver,
    PumpBatteryObserver,
    PumpReservoirObserver
{
    func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
    }

    func suggestionDidUpdate(_ suggestion: Suggestion) {
        self.suggestion = suggestion
        carbsRequired = suggestion.carbsReq
        setStatusTitle()
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
        screenHours = settingsManager.settings.hours
        displayXgridLines = settingsManager.settings.xGridLines
        displayYgridLines = settingsManager.settings.yGridLines
        thresholdLines = settingsManager.settings.rulerMarks

        setupGlucose()
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupBasals()
        setupBoluses()
        setupSuspensions()
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

    func carbsDidUpdate(_: [CarbsEntry]) {
        setupCarbs()
    }

    func enactedSuggestionDidUpdate(_ suggestion: Suggestion) {
        enactedSuggestion = suggestion
        setStatusTitle()
    }

    func pumpBatteryDidChange(_: Battery) {
        setupBattery()
    }

    func pumpReservoirDidChange(_: Decimal) {
        setupReservoir()
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
