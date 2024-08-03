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
    @Injected() private var apsManager: APSManager!
    @Injected() private var storage: FileStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var garmin: GarminManager!

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
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = settingsManager.settings.units == .mmolL ? 1 : 0
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        return formatter
    }

    private var targetFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    let context = CoreDataStack.shared.newTaskContext()
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    private var coreDataObserver: CoreDataObserver?

    private var lifetime = Lifetime()

    init(resolver: Resolver, session: WCSession = .default) {
        self.session = session
        super.init()
        injectServices(resolver)
        setupNotification()
        coreDataObserver = CoreDataObserver()
        registerHandlers()
        Task {
            await configureState()
        }

        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }

        broadcaster.register(SettingsObserver.self, observer: self)
        broadcaster.register(PumpHistoryObserver.self, observer: self)
        broadcaster.register(PumpSettingsObserver.self, observer: self)
        broadcaster.register(BasalProfileObserver.self, observer: self)
        broadcaster.register(TempTargetsObserver.self, observer: self)
        broadcaster.register(CarbsObserver.self, observer: self)
        broadcaster.register(PumpBatteryObserver.self, observer: self)
        broadcaster.register(PumpReservoirObserver.self, observer: self)
        garmin.stateRequet = { [weak self] () -> Data in
            guard let self = self, let data = try? JSONEncoder().encode(self.state) else {
                warning(.service, "Cannot encode watch state")
                return Data()
            }
            return data
        }

        Task {
            await configureState()
        }
    }

    func setupNotification() {
        /// custom notification that is sent when a batch insert of glucose objects is done
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBatchInsert),
            name: .didPerformBatchInsert,
            object: nil
        )
    }

    @objc private func handleBatchInsert() {
        Task {
            await self.configureState()
        }
    }

    private func registerHandlers() {
        coreDataObserver?.registerHandler(for: "OrefDetermination") { [weak self] in
            guard let self = self else { return }
            Task {
                await self.configureState()
            }
        }
        coreDataObserver?.registerHandler(for: "OverrideStored") { [weak self] in
            guard let self = self else { return }
            Task {
                await self.configureState()
            }
        }
        // Observes Deletion of Glucose Objects
        coreDataObserver?.registerHandler(for: "GlucoseStored") { [weak self] in
            guard let self = self else { return }
            Task {
                await self.configureState()
            }
        }
    }

    private func fetchlastDetermination() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.enactedDetermination,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        guard let fetchedResults = results as? [OrefDetermination] else { return [] }

        return await context.perform {
            fetchedResults.map(\.objectID)
        }
    }

    private func fetchLatestOverride() async -> NSManagedObjectID? {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["enabled", "percentage", "objectID"]
        )

        guard let fetchedResults = results as? [[String: Any]] else { return nil }

        return await context.perform {
            fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }.first
        }
    }

    private func fetchGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateFor120MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 24,
            batchSize: 12
        )

        guard let glucoseResults = results as? [GlucoseStored] else {
            return []
        }

        return await context.perform {
            glucoseResults.map(\.objectID)
        }
    }

    @MainActor private func configureState() async {
        let glucoseValuesIDs = await fetchGlucose()
        guard let lastDeterminationID = await fetchlastDetermination().first,
              let latestOverrideID = await fetchLatestOverride() else { return }

        do {
            let glucoseValues = try glucoseValuesIDs.compactMap { id in
                try viewContext.existingObject(with: id) as? GlucoseStored
            }

            let lastDetermination = try viewContext.existingObject(with: lastDeterminationID) as? OrefDetermination
            let latestOverride = try viewContext.existingObject(with: latestOverrideID) as? OverrideStored

            if let firstGlucoseValue = glucoseValues.first {
                let value = settingsManager.settings
                    .units == .mgdL ? Decimal(firstGlucoseValue.glucose) : Decimal(firstGlucoseValue.glucose).asMmolL
                state.glucose = glucoseFormatter.string(from: value as NSNumber)
                state.trend = firstGlucoseValue.direction
                let delta = glucoseValues
                    .count >= 2 ? Decimal(firstGlucoseValue.glucose) - Decimal(glucoseValues.dropFirst().first?.glucose ?? 0) : 0
                let deltaConverted = settingsManager.settings.units == .mgdL ? delta : delta.asMmolL
                state.delta = deltaFormatter.string(from: deltaConverted as NSNumber)
                state.trendRaw = firstGlucoseValue.direction
                state.glucoseDate = firstGlucoseValue.date
            }

            state.lastLoopDate = lastDetermination?.timestamp
            state.lastLoopDateInterval = state.lastLoopDate.map {
                guard $0.timeIntervalSince1970 > 0 else { return 0 }
                return UInt64($0.timeIntervalSince1970)
            }
            state.bolusIncrement = settingsManager.preferences.bolusIncrement
            state.maxCOB = settingsManager.preferences.maxCOB
            state.maxBolus = settingsManager.pumpSettings.maxBolus
            state.carbsRequired = lastDetermination?.carbsRequired as? Decimal

            var insulinRequired = lastDetermination?.insulinReq as? Decimal ?? 0

            var double: Decimal = 2
            if lastDetermination?.manualBolusErrorString == 0 {
                insulinRequired = lastDetermination?.insulinForManualBolus as? Decimal ?? 0
                double = 1
            }

            state.useNewCalc = settingsManager.settings.useCalc

            if !(state.useNewCalc ?? false) {
                state.bolusRecommended = apsManager
                    .roundBolus(amount: max(
                        insulinRequired * (settingsManager.settings.insulinReqPercentage / 100) * double,
                        0
                    ))
            } else {
                let recommended = await newBolusCalc(
                    ids: glucoseValuesIDs,
                    determination: lastDetermination
                )
                state.bolusRecommended = apsManager
                    .roundBolus(amount: max(recommended, 0))
            }
            state.bolusAfterCarbs = !settingsManager.settings.skipBolusScreenAfterCarbs
            state.displayOnWatch = settingsManager.settings.displayOnWatch
            state.displayFatAndProteinOnWatch = settingsManager.settings.displayFatAndProteinOnWatch
            state.confirmBolusFaster = settingsManager.settings.confirmBolusFaster

            state.iob = lastDetermination?.iob as? Decimal
            state.cob = lastDetermination?.cob as? Decimal
            state.tempTargets = tempTargetsStorage.presets()
                .map { target -> TempTargetWatchPreset in
                    let untilDate = self.tempTargetsStorage.current().flatMap { currentTarget -> Date? in
                        guard currentTarget.id == target.id else { return nil }
                        let date = currentTarget.createdAt.addingTimeInterval(TimeInterval(currentTarget.duration * 60))
                        return date > Date() ? date : nil
                    }
                    return TempTargetWatchPreset(
                        name: target.displayName,
                        id: target.id,
                        description: self.descriptionForTarget(target),
                        until: untilDate
                    )
                }
            state.bolusAfterCarbs = !settingsManager.settings.skipBolusScreenAfterCarbs
            state.displayOnWatch = settingsManager.settings.displayOnWatch
            state.displayFatAndProteinOnWatch = settingsManager.settings.displayFatAndProteinOnWatch
            state.confirmBolusFaster = settingsManager.settings.confirmBolusFaster

            if let eventualBG = settingsManager.settings.units == .mgdL ? lastDetermination?.eventualBG : lastDetermination?
                .eventualBG?.decimalValue.asMmolL as NSDecimalNumber?
            {
                let eventualBGAsString = eventualFormatter.string(from: eventualBG)
                state.eventualBG = eventualBGAsString.map { "⇢ " + $0 }
                state.eventualBGRaw = eventualBGAsString
            }

            state.isf = lastDetermination?.insulinSensitivity as? Decimal

            if latestOverride?.enabled ?? false {
                let percentString = "\((latestOverride?.percentage ?? 100).formatted(.number)) %"
                state.override = percentString

            } else {
                state.override = "100 %"
            }

            sendState()

        } catch let error as NSError {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to configure state with error: \(error)")
        }
    }

    private func sendState() {
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

    private func descriptionForTarget(_ target: TempTarget) -> String {
        let units = settingsManager.settings.units

        var low = target.targetBottom
        var high = target.targetTop
        if units == .mmolL {
            low = low?.asMmolL
            high = high?.asMmolL
        }

        let description =
            "\(targetFormatter.string(from: (low ?? 0) as NSNumber)!) - \(targetFormatter.string(from: (high ?? 0) as NSNumber)!)" +
            " for \(targetFormatter.string(from: target.duration as NSNumber)!) min"

        return description
    }

    private func newBolusCalc(ids: [NSManagedObjectID], determination: OrefDetermination?) async -> Decimal {
        await context.perform {
            let glucoseObjects = ids.compactMap { self.context.object(with: $0) as? GlucoseStored }
            guard let firstGlucose = glucoseObjects.first else {
                return 0 // If there's no glucose data, exit the block
            }
            let bg = firstGlucose.glucose // Make sure to provide a fallback value for glucose

            // Calculations related to glucose data
            var bgDelta: Int = 0
            if glucoseObjects.count >= 3 {
                bgDelta = Int(firstGlucose.glucose) - Int(glucoseObjects[2].glucose)
            }

            let conversion: Decimal = self.settingsManager.settings.units == .mmolL ? 0.0555 : 1
            let isf = self.state.isf ?? 0
            let target = determination?.currentTarget as? Decimal ?? 100
            let carbratio = determination?.carbRatio as? Decimal ?? 10
            let cob = self.state.cob ?? 0
            let iob = self.state.iob ?? 0
            let fattyMealFactor = self.settingsManager.settings.fattyMealFactor

            // Complete bolus calculation logic
            let targetDifference = Decimal(bg) - target
            let targetDifferenceInsulin = targetDifference * conversion / isf
            let fifteenMinInsulin = Decimal(bgDelta) * conversion / isf
            let wholeCobInsulin = cob / carbratio
            let iobInsulinReduction = -iob
            let wholeCalc = targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin + fifteenMinInsulin

            let result = wholeCalc * self.settingsManager.settings.overrideFactor
            var insulinCalculated: Decimal
            if self.settingsManager.settings.fattyMeals {
                insulinCalculated = result * fattyMealFactor
            } else {
                insulinCalculated = result
            }

            // Ensure the calculated insulin amount does not exceed the maximum bolus and is not below zero
            insulinCalculated = max(min(insulinCalculated, self.settingsManager.pumpSettings.maxBolus), 0)
            return insulinCalculated // Return the calculated insulin outside of the performAndWait block
        }
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
            Task {
                await carbsStorage.storeCarbs(
                    [CarbsEntry(
                        id: UUID().uuidString,
                        createdAt: Date(),
                        actualDate: nil,
                        carbs: Decimal(carbs),
                        fat: Decimal(fat),
                        protein: Decimal(protein),
                        note: nil,
                        enteredBy: CarbsEntry.manual,
                        isFPU: false,
                        fpuID: nil
                    )]
                )

                if settingsManager.settings.skipBolusScreenAfterCarbs {
                    let success = await apsManager.determineBasal()
                    replyHandler(["confirmation": success])
                } else {
                    _ = await apsManager.determineBasal()
                    replyHandler(["confirmation": true])
                }
            }
            return
        }

        if let tempTargetID = message["tempTarget"] as? String {
            Task {
                if var preset = tempTargetsStorage.presets().first(where: { $0.id == tempTargetID }) {
                    preset.createdAt = Date()
                    tempTargetsStorage.storeTempTargets([preset])
                    replyHandler(["confirmation": true])
                } else if tempTargetID == "cancel" {
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
                    replyHandler(["confirmation": true])
                } else {
                    replyHandler(["confirmation": false])
                }
            }
            return
        }

        if let bolus = message["bolus"] as? Double, bolus > 0 {
            Task {
                await apsManager.enactBolus(amount: bolus, isSMB: false)
                replyHandler(["confirmation": true])
            }
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
    SettingsObserver,
    PumpHistoryObserver,
    PumpSettingsObserver,
    BasalProfileObserver,
    TempTargetsObserver,
    CarbsObserver,
    PumpBatteryObserver,
    PumpReservoirObserver
{
    func settingsDidChange(_: FreeAPSSettings) {
        Task {
            await configureState()
        }
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        // TODO:
    }

    func pumpSettingsDidChange(_: PumpSettings) {
        Task {
            await configureState()
        }
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) {
        // TODO:
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        Task {
            await configureState()
        }
    }

    func carbsDidUpdate(_: [CarbsEntry]) {
        // TODO:
    }

    func pumpBatteryDidChange(_: Battery) {
        // TODO:
    }

    func pumpReservoirDidChange(_: Decimal) {
        // TODO:
    }
}
