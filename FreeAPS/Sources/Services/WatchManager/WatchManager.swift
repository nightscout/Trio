import CoreData
import Foundation
import Swinject
import WatchConnectivity

protocol WatchManager {}

final class BaseWatchManager: NSObject, WatchManager, Injectable {
    private let session: WCSession
    private var state = WatchState()
    private let processQueue = DispatchQueue(label: "BaseWatchManager.processQueue")

    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var storage: FileStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var overrideStorage: OverrideStorage!
    @Injected() private var garmin: GarminManager!

    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext // newBackgroundContext()

    private var lifetime = Lifetime()

    init(resolver: Resolver, session: WCSession = .default) {
        self.session = session
        super.init()
        injectServices(resolver)

        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }

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
        broadcaster.register(OverrideObserver.self, observer: self)
        garmin.stateRequet = { [weak self] () -> Data in
            guard let self = self, let data = try? JSONEncoder().encode(self.state) else {
                warning(.service, "Cannot encode watch state")
                return Data()
            }
            return data
        }

        configureState()
    }

    private func configureState() {
        processQueue.async {
            let glucoseValues = self.glucoseText()
            self.state.glucose = glucoseValues.glucose
            self.state.trend = glucoseValues.trend
            self.state.delta = glucoseValues.delta
            self.state.trendRaw = self.glucoseStorage.recent().last?.direction?.rawValue
            self.state.glucoseDate = self.glucoseStorage.recent().last?.dateString
            self.state.glucoseDateInterval = self.state.glucoseDate.map { UInt64($0.timeIntervalSince1970) }
            self.state.lastLoopDate = self.enactedSuggestion?.recieved == true ? self.enactedSuggestion?.deliverAt : self
                .apsManager.lastLoopDate
            self.state.lastLoopDateInterval = self.state.lastLoopDate.map {
                guard $0.timeIntervalSince1970 > 0 else { return 0 }
                return UInt64($0.timeIntervalSince1970)
            }
            self.state.bolusIncrement = self.settingsManager.preferences.bolusIncrement
            self.state.maxCOB = self.settingsManager.preferences.maxCOB
            self.state.maxBolus = self.settingsManager.pumpSettings.maxBolus
            self.state.carbsRequired = self.suggestion?.carbsReq

            var insulinRequired = self.suggestion?.insulinReq ?? 0
            var double: Decimal = 2
            if (self.suggestion?.cob ?? 0) > 0 {
                if self.suggestion?.manualBolusErrorString == 0 {
                    insulinRequired = self.suggestion?.insulinForManualBolus ?? 0
                    double = 1
                }
            }

            self.state.bolusRecommended = self.apsManager
                .roundBolus(amount: max(insulinRequired * (self.settingsManager.settings.insulinReqPercentage / 100) * double, 0))

            self.state.iob = self.suggestion?.iob
            self.state.cob = self.suggestion?.cob
            self.state.bolusAfterCarbs = !self.settingsManager.settings.skipBolusScreenAfterCarbs
            self.state.displayOnWatch = self.settingsManager.settings.displayOnWatch
            self.state.displayFatAndProteinOnWatch = self.settingsManager.settings.displayFatAndProteinOnWatch
            let eBG = self.evetualBGStraing()
            self.state.eventualBG = eBG.map { "⇢ " + $0 }
            self.state.eventualBGRaw = eBG

            self.state.isf = self.suggestion?.isf

            // add temp preset
            var presetTempTargetSelected: Bool = false
            var tempTargetPresetArray = self.tempTargetsStorage.presets()
                .map { target -> TempTargetWatchPreset in
                    let untilDate = self.tempTargetsStorage.current().flatMap { currentTarget -> Date? in
                        guard currentTarget.id == target.id else { return nil }
                        let date = currentTarget.createdAt.addingTimeInterval(TimeInterval(currentTarget.duration * 60))
                        return date > Date() ? date : nil
                    }
                    if untilDate != nil { presetTempTargetSelected = true }
                    return TempTargetWatchPreset(
                        name: target.displayName,
                        id: target.id,
                        description: self.descriptionForTarget(target),
                        until: untilDate,
                        typeTempTarget: .tempTarget
                    )
                }

            // add a specific temp target  in progress if this temp target is not a preset
            if let current = self.tempTargetsStorage.current(), !presetTempTargetSelected {
                tempTargetPresetArray.append(
                    TempTargetWatchPreset(
                        name: "Custom",
                        id: current.id,
                        description: self.descriptionForTarget(current),
                        until: current.createdAt.addingTimeInterval(TimeInterval(Double(current.duration) * 60)),
                        typeTempTarget: .tempTarget
                    )
                )
            }

            // add override in the temp target list
            let current = self.overrideStorage.current()
            if current != nil {
                let percentString = "\((current?.percentage ?? 100).formatted(.number)) %"
                self.state.override = percentString

            } else {
                self.state.override = "100 %"
            }

            var presetOverrideSelected: Bool = false
            var overridePresetArray: [TempTargetWatchPreset] = self.overrideStorage.presets().compactMap { target in
                var untilDate: Date?

                if let date = current?.createdAt, current?.name == target.name
                {
                    // duration = 0 -> unlimited duration = 1 year
                    let duration = target.duration ?? (24 * 60 * 365)
                    untilDate = date.addingTimeInterval(TimeInterval(duration * 60))
                    presetOverrideSelected = true
                } else {
                    untilDate = nil
                }

                return TempTargetWatchPreset(
                    name: target.name ?? "",
                    id: target.id,
                    description: "Profil : \(target.percentage ?? 100) %",
                    until: untilDate,
                    typeTempTarget: .override
                )
            }

            // add a specific override profil in progress if this override is not a preset
            if let current = current, !presetOverrideSelected {
                let duration = current.duration ?? (24 * 60 * 365)
                let date = current.createdAt
                let untilDate = date?.addingTimeInterval(TimeInterval(duration * 60))
                overridePresetArray.append(
                    TempTargetWatchPreset(
                        name: "Custom",
                        id: current.id,
                        description: "Profil : \(current.percentage ?? 100) %",
                        until: untilDate,
                        typeTempTarget: .override
                    )
                )
            }

            self.state.tempTargets = tempTargetPresetArray + overridePresetArray

            self.sendState()
        }
    }

    private func sendState() {
        dispatchPrecondition(condition: .onQueue(processQueue))
        guard let data = try? JSONEncoder().encode(state) else {
            warning(.service, "Cannot encode watch state")
            return
        }

        garmin.sendState(data)

        guard session.isReachable else { return }
        session.sendMessageData(data, replyHandler: nil) { error in
            warning(.service, "Cannot send message to watch", error: error)
        }
    }

    private func glucoseText() -> (glucose: String, trend: String, delta: String) {
        let glucose = glucoseStorage.recent()

        guard let lastGlucose = glucose.last, let glucoseValue = lastGlucose.glucose else { return ("--", "--", "--") }

        let delta = glucose.count >= 2 ? glucoseValue - (glucose[glucose.count - 2].glucose ?? 0) : nil

        let units = settingsManager.settings.units
        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? glucoseValue
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!
        let directionText = lastGlucose.direction?.symbol ?? "↔︎"
        let deltaText = delta
            .map {
                self.deltaFormatter
                    .string(from: Double(
                        units == .mmolL ? $0
                            .asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return (glucoseText, directionText, deltaText)
    }

    private func descriptionForTarget(_ target: TempTarget) -> String {
        let units = settingsManager.settings.units

        var low = target.targetBottom
        if units == .mmolL {
            low = low?.asMmolL
        }

        let description =
            "\(targetFormatter.string(from: (low ?? 0) as NSNumber)!) " +
            " for \(targetFormatter.string(from: target.duration as NSNumber)!) min"

        return description
    }

    private func evetualBGStraing() -> String? {
        guard let eventualBG = suggestion?.eventualBG else {
            return nil
        }
        let units = settingsManager.settings.units
        return eventualFormatter.string(
            from: (units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
        )!
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var eventualFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }

    private var targetFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var suggestion: Suggestion? {
        storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
    }

    private var enactedSuggestion: Suggestion? {
        storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)
    }
}

extension BaseWatchManager: WCSessionDelegate {
    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_: WCSession) {}

    func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error _: Error?) {
        debug(.service, "WCSession is activated: \(state == .activated)")
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        debug(.service, "WCSession got message: \(message)")

        if let stateRequest = message["stateRequest"] as? Bool, stateRequest {
            processQueue.async {
                self.sendState()
            }
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        debug(.service, "WCSession got message with reply handler: \(message)")

        if let carbs = message["carbs"] as? Double,
           let fat = message["fat"] as? Double,
           let protein = message["protein"] as? Double,
           carbs > 0 || fat > 0 || protein > 0
        {
            carbsStorage.storeCarbs(
                [CarbsEntry(
                    id: UUID().uuidString,
                    createdAt: Date.now,
                    carbs: Decimal(carbs),
                    fat: Decimal(fat),
                    protein: Decimal(protein), note: nil,
                    enteredBy: CarbsEntry.manual,
                    isFPU: false, fpuID: nil
                )]
            )

            if settingsManager.settings.skipBolusScreenAfterCarbs {
                apsManager.determineBasalSync()
                replyHandler(["confirmation": true])
                return
            } else {
                apsManager.determineBasal()
                    .sink { _ in
                        replyHandler(["confirmation": true])
                    }
                    .store(in: &lifetime)
                return
            }
        }

        if let tempTargetID = message["tempTarget"] as? String {
            if var preset = tempTargetsStorage.presets().first(where: { $0.id == tempTargetID }) {
                preset.createdAt = Date()
                tempTargetsStorage.storeTempTargets([preset])
            }
            replyHandler(["confirmation": true])
            return
        }

        if let tempTargetID = message["overrideTarget"] as? String {
            _ = overrideStorage.applyOverridePreset(tempTargetID)
            replyHandler(["confirmation": true])
            return
        }

        if let _ = message["cancelTempTarget"] as? String {
            let entry = TempTarget(
                name: TempTarget.cancel,
                createdAt: Date(),
                targetTop: 0,
                targetBottom: 0,
                duration: 0,
                enteredBy: TempTarget.manual,
                reason: TempTarget.cancel
            )
            tempTargetsStorage.storeTempTargets([entry])

            _ = overrideStorage.cancelCurrentOverride()

            replyHandler(["confirmation": true])
            return
        }

        if let bolus = message["bolus"] as? Double, bolus > 0 {
            apsManager.enactBolus(amount: bolus, isSMB: false)
            replyHandler(["confirmation": true])
            return
        }

        replyHandler(["confirmation": false])
    }

    func session(_: WCSession, didReceiveMessageData _: Data) {}

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            processQueue.async {
                self.sendState()
            }
        }
    }
}

extension BaseWatchManager:
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
    PumpReservoirObserver,
    OverrideObserver
{
    func overrideDidUpdate(_: [OverrideProfil?]) {
        configureState()
    }

    func glucoseDidUpdate(_: [BloodGlucose]) {
        configureState()
    }

    func suggestionDidUpdate(_: Suggestion) {
        configureState()
    }

    func settingsDidChange(_: FreeAPSSettings) {
        configureState()
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        // TODO:
    }

    func pumpSettingsDidChange(_: PumpSettings) {
        configureState()
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) {
        // TODO:
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        configureState()
    }

    func carbsDidUpdate(_: [CarbsEntry]) {
        // TODO:
    }

    func enactedSuggestionDidUpdate(_: Suggestion) {
        configureState()
    }

    func pumpBatteryDidChange(_: Battery) {
        // TODO:
    }

    func pumpReservoirDidChange(_: Decimal) {
        // TODO:
    }
}
