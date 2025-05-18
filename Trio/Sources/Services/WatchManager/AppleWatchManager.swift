import Combine
import CoreData
import Foundation
import Swinject
import UIKit
import WatchConnectivity

/// Protocol defining the base functionality for Watch communication
protocol WatchManager {
    func setupWatchState() async -> WatchState
}

/// Main implementation of the Watch communication manager
/// Handles bidirectional communication between iPhone and Apple Watch
final class BaseWatchManager: NSObject, WCSessionDelegate, Injectable, WatchManager {
    private var session: WCSession?

    @Injected() var broadcaster: Broadcaster!
    @Injected() private var apsManager: APSManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var fileStorage: FileStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var determinationStorage: DeterminationStorage!
    @Injected() private var overrideStorage: OverrideStorage!
    @Injected() private var tempTargetStorage: TempTargetsStorage!
    @Injected() private var bolusCalculationManager: BolusCalculationManager!

    private var units: GlucoseUnits = .mgdL
    private var glucoseColorScheme: GlucoseColorScheme = .staticColor
    private var lowGlucose: Decimal = 70.0
    private var highGlucose: Decimal = 180.0
    private var currentGlucoseTarget: Decimal = 100.0
    private var activeBolusAmount: Double = 0.0

    // Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseWatchManagerManager.queue", qos: .utility)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    typealias PumpEvent = PumpEventStored.EventType

    let backgroundContext = CoreDataStack.shared.newTaskContext()
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)
        setupWatchSession()

        units = settingsManager.settings.units
        glucoseColorScheme = settingsManager.settings.glucoseColorScheme
        lowGlucose = settingsManager.settings.low
        highGlucose = settingsManager.settings.high
        Task {
            currentGlucoseTarget = await getCurrentGlucoseTarget() ?? Decimal(100)
        }
        broadcaster.register(SettingsObserver.self, observer: self)
        broadcaster.register(PumpSettingsObserver.self, observer: self)

        // Observer for OrefDetermination and adjustments
        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        // Observer for glucose and manual glucose
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    let state = await self.setupWatchState()
                    await self.sendDataToWatch(state)
                }
            }
            .store(in: &subscriptions)

        registerHandlers()
    }

    private func registerHandlers() {
        coreDataPublisher?.filteredByEntityName("OrefDetermination").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                let state = await self.setupWatchState()
                await self.sendDataToWatch(state)
            }
        }.store(in: &subscriptions)

        // Due to the Batch insert this only is used for observing Deletion of Glucose entries
        coreDataPublisher?.filteredByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                let state = await self.setupWatchState()
                await self.sendDataToWatch(state)
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filteredByEntityName("PumpEventStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.getActiveBolusAmount()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filteredByEntityName("OverrideStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                let state = await self.setupWatchState()
                await self.sendDataToWatch(state)
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filteredByEntityName("TempTargetStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                let state = await self.setupWatchState()
                await self.sendDataToWatch(state)
            }
        }.store(in: &subscriptions)
    }

    /// Sets up the WatchConnectivity session if the device supports it
    private func setupWatchSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            self.session = session

            debug(.watchManager, "📱 Phone session setup - isPaired: \(session.isPaired)")
        } else {
            debug(.watchManager, "📱 WCSession is not supported on this device")
        }
    }

    /// Attempts to reestablish the Watch connection if it becomes unreachable
    private func retryConnection() {
        guard let session = session else { return }

        if !session.isReachable {
            debug(.watchManager, "📱 Attempting to reactivate session...")
            session.activate()
        }
    }

    /// Prepares the current state data to be sent to the Watch
    /// - Returns: WatchState containing current glucose readings and trends and determination infos for displaying cob and iob in the view
    func setupWatchState() async -> WatchState {
        do {
            // Get NSManagedObjectIDs
            let glucoseIds = try await fetchGlucose()
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.predicateFor30MinAgoForDetermination
            )
            let overridePresetIds = try await overrideStorage.fetchForOverridePresets()
            let tempTargetPresetIds = try await tempTargetStorage.fetchForTempTargetPresets()

            // Get NSManagedObjects
            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: glucoseIds, context: backgroundContext)
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared
                .getNSManagedObject(with: determinationIds, context: backgroundContext)
            let overridePresetObjects: [OverrideStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: overridePresetIds, context: backgroundContext)
            let tempTargetPresetObjects: [TempTargetStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: tempTargetPresetIds, context: backgroundContext)

            return await backgroundContext.perform {
                var watchState = WatchState(date: Date())

                // Set lastLoopDate
                let lastLoopMinutes = Int((Date().timeIntervalSince(self.apsManager.lastLoopDate) - 30) / 60) + 1
                if lastLoopMinutes > 1440 {
                    watchState.lastLoopTime = "--"
                } else {
                    watchState.lastLoopTime = "\(lastLoopMinutes) min"
                }

                // Set IOB and COB from latest determination
                if let latestDetermination = determinationObjects.first {
                    let iob = latestDetermination.iob ?? 0
                    watchState.iob = Formatter.decimalFormatterWithTwoFractionDigits.string(from: iob)

                    let cob = NSNumber(value: latestDetermination.cob)
                    watchState.cob = Formatter.integerFormatter.string(from: cob)
                }

                // Set override presets with their enabled status
                watchState.overridePresets = overridePresetObjects.map { override in
                    OverridePresetWatch(
                        name: override.name ?? "",
                        isEnabled: override.enabled
                    )
                }

                guard let latestGlucose = glucoseObjects.first else {
                    return watchState
                }

                // Assign currentGlucose and its color
                /// Set current glucose with proper formatting
                if self.units == .mgdL {
                    watchState.currentGlucose = "\(latestGlucose.glucose)"
                } else {
                    let mgdlValue = Decimal(latestGlucose.glucose)
                    let latestGlucoseValue = mgdlValue.formattedAsMmolL
                    watchState.currentGlucose = "\(latestGlucoseValue)"
                }

                /// Calculate latest color
                let hardCodedLow = Decimal(55)
                let hardCodedHigh = Decimal(220)
                let isDynamicColorScheme = self.glucoseColorScheme == .dynamicColor

                let highGlucoseValue = isDynamicColorScheme ? hardCodedHigh : self.highGlucose
                let lowGlucoseValue = isDynamicColorScheme ? hardCodedLow : self.lowGlucose
                let highGlucoseColorValue = highGlucoseValue
                let lowGlucoseColorValue = lowGlucoseValue
                let targetGlucose = self.currentGlucoseTarget

                let currentGlucoseColor = Trio.getDynamicGlucoseColor(
                    glucoseValue: Decimal(latestGlucose.glucose),
                    highGlucoseColorValue: highGlucoseColorValue,
                    lowGlucoseColorValue: lowGlucoseColorValue,
                    targetGlucose: targetGlucose,
                    glucoseColorScheme: self.glucoseColorScheme
                )

                if Decimal(latestGlucose.glucose) <= self.lowGlucose || Decimal(latestGlucose.glucose) >= self.highGlucose {
                    watchState.currentGlucoseColorString = currentGlucoseColor.toHexString()
                } else {
                    watchState.currentGlucoseColorString = "#ffffff" // white when in range; colored when out of range
                }

                // Map glucose values
                watchState.glucoseValues = glucoseObjects.compactMap { glucose in
                    let glucoseValue = self.units == .mgdL
                        ? Double(glucose.glucose)
                        : Double(truncating: Decimal(glucose.glucose).asMmolL as NSNumber)

                    let glucoseColor = Trio.getDynamicGlucoseColor(
                        glucoseValue: Decimal(glucose.glucose),
                        highGlucoseColorValue: highGlucoseColorValue,
                        lowGlucoseColorValue: lowGlucoseColorValue,
                        targetGlucose: targetGlucose,
                        glucoseColorScheme: self.glucoseColorScheme
                    )

                    return WatchGlucoseObject(
                        date: glucose.date ?? Date(),
                        glucose: glucoseValue,
                        color: glucoseColor.toHexString()
                    )
                }
                .sorted { $0.date < $1.date }

                // Set axis domain: min and max Y-axis values
                // Apply unit parsing conditionally, if user uses mmol/L
                let maxGlucoseValue = Decimal(glucoseObjects.map { Int($0.glucose) }.max() ?? 200)
                var maxYValue = Decimal(200)

                if maxGlucoseValue > maxYValue, maxGlucoseValue <= 225 {
                    maxYValue = Decimal(250)
                } else if maxGlucoseValue > 225, maxGlucoseValue <= 275 {
                    maxYValue = Decimal(300)
                } else if maxGlucoseValue > 275, maxGlucoseValue <= 325 {
                    maxYValue = Decimal(350)
                } else if maxGlucoseValue > 325 {
                    maxYValue = Decimal(400)
                }

                if self.units == .mmolL {
                    maxYValue = Double(truncating: maxYValue as NSNumber).asMmolL
                }
                watchState.maxYAxisValue = maxYValue

                if self.units == .mmolL {
                    let minYValue = Double(truncating: watchState.minYAxisValue as NSNumber).asMmolL
                    watchState.minYAxisValue = minYValue
                }

                // Convert direction to trend string
                watchState.trend = latestGlucose.direction

                // Calculate delta if we have at least 2 readings
                if glucoseObjects.count >= 2 {
                    var deltaValue = Decimal(glucoseObjects[0].glucose - glucoseObjects[1].glucose)

                    if self.units == .mmolL {
                        deltaValue = Double(truncating: deltaValue as NSNumber).asMmolL
                    }

                    let formattedDelta = Formatter.glucoseFormatter(for: self.units)
                        .string(from: deltaValue as NSNumber) ?? "0"
                    watchState.delta = deltaValue < 0 ? "\(formattedDelta)" : "+\(formattedDelta)"
                }

                // Set temp target presets with their enabled status
                watchState.tempTargetPresets = tempTargetPresetObjects.map { tempTarget in
                    TempTargetPresetWatch(
                        name: tempTarget.name ?? "",
                        isEnabled: tempTarget.enabled
                    )
                }

                // Set units
                watchState.units = self.units

                // Add limits and pump specific dosing increment settings values
                watchState.maxBolus = self.settingsManager.pumpSettings.maxBolus
                watchState.maxCarbs = self.settingsManager.settings.maxCarbs
                watchState.maxFat = self.settingsManager.settings.maxFat
                watchState.maxProtein = self.settingsManager.settings.maxProtein
                watchState.bolusIncrement = self.settingsManager.preferences.bolusIncrement
                watchState.confirmBolusFaster = self.settingsManager.settings.confirmBolusFaster

                debug(
                    .watchManager,

                    "📱 Setup WatchState - currentGlucose: \(watchState.currentGlucose ?? "nil"), trend: \(watchState.trend ?? "nil"), delta: \(watchState.delta ?? "nil"), values: \(watchState.glucoseValues.count)"
                )

                return watchState
            }
        } catch {
            debug(
                .watchManager,
                "\(DebuggingIdentifiers.failed) Error setting up watch state: \(error)"
            )
            // Return empty state in case of error
            return WatchState(date: Date())
        }
    }

    /// Fetches recent glucose readings from CoreData
    /// - Returns: Array of NSManagedObjectIDs for glucose readings
    private func fetchGlucose() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        return try await backgroundContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    /// Fetches last pump event that is a non-external bolus from CoreData
    /// - Returns: NSManagedObjectIDs for last bolus
    func fetchLastBolus() async throws -> NSManagedObjectID? {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.lastPumpBolus,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        return try await backgroundContext.perform {
            guard let fetchedResults = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID).first
        }
    }

    /// Gets the active bolus amount by fetching last (active) bolus.
    @MainActor func getActiveBolusAmount() async {
        do {
            if let lastBolusObjectId = try await fetchLastBolus() {
                let lastBolusObject: [PumpEventStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: [lastBolusObjectId], context: viewContext)

                activeBolusAmount = lastBolusObject.first?.bolus?.amount?.doubleValue ?? 0.0
            }
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Error getting active bolus amount: \(error)"
            )
        }
    }

    // MARK: - Send to Watch

    func watchStateToDictionary(from state: WatchState) -> [String: Any] {
        [
            WatchMessageKeys.date: state.date.timeIntervalSince1970,
            WatchMessageKeys.currentGlucose: state.currentGlucose ?? "--",
            WatchMessageKeys.currentGlucoseColorString: state.currentGlucoseColorString ?? "#ffffff",
            WatchMessageKeys.trend: state.trend ?? "",
            WatchMessageKeys.delta: state.delta ?? "",
            WatchMessageKeys.iob: state.iob ?? "",
            WatchMessageKeys.cob: state.cob ?? "",
            WatchMessageKeys.lastLoopTime: state.lastLoopTime ?? "",
            WatchMessageKeys.glucoseValues: state.glucoseValues.map { value in
                [
                    "glucose": value.glucose,
                    "date": value.date.timeIntervalSince1970,
                    "color": value.color
                ]
            },
            WatchMessageKeys.minYAxisValue: state.minYAxisValue,
            WatchMessageKeys.maxYAxisValue: state.maxYAxisValue,
            WatchMessageKeys.overridePresets: state.overridePresets.map { preset in
                [
                    "name": preset.name,
                    "isEnabled": preset.isEnabled
                ]
            },
            WatchMessageKeys.tempTargetPresets: state.tempTargetPresets.map { preset in
                [
                    "name": preset.name,
                    "isEnabled": preset.isEnabled
                ]
            },
            WatchMessageKeys.maxBolus: state.maxBolus,
            WatchMessageKeys.maxCarbs: state.maxCarbs,
            WatchMessageKeys.maxFat: state.maxFat,
            WatchMessageKeys.maxProtein: state.maxProtein,
            WatchMessageKeys.bolusIncrement: state.bolusIncrement,
            WatchMessageKeys.confirmBolusFaster: state.confirmBolusFaster,
            WatchMessageKeys.units: state.units.rawValue
        ]
    }

    /// Sends the state of type WatchState to the connected Watch
    /// - Parameter state: Current WatchState containing glucose data to be sent
    @MainActor func sendDataToWatch(_ state: WatchState) async {
        guard let session = session else { return }

        guard session.isPaired else {
            debug(.watchManager, "⌚️❌ No Watch is paired")
            return
        }

        guard session.isWatchAppInstalled else {
            debug(.watchManager, "⌚️❌ Trio Watch app is")
            return
        }

        guard session.activationState == .activated else {
            let activationStateString = "\(session.activationState)"
            debug(.watchManager, "⌚️ Watch session activationState = \(activationStateString). Reactivating...")
            session.activate()
            return
        }

        // Skip if we already sent this state or older
        let lastSent = WatchStateSnapshot.loadLatestDateFromDisk()
        guard lastSent < state.date else {
            debug(.watchManager, "🕐 Skipping push — newer or equal state already sent")
            return
        }

        let message: [String: Any] = watchStateToDictionary(from: state)

        // if session is reachable, it means watch App is in the foreground -> send watchState as message
        // if session is not reachable, it means it's in background -> send watchState as userInfo
        if session.isReachable {
            session.sendMessage([WatchMessageKeys.watchState: message], replyHandler: nil) { error in
                debug(.watchManager, "❌ Error sending watch state: \(error)")
            }
            WatchStateSnapshot.saveLatestDateToDisk(state.date)
        } else {
            WatchStateSnapshot.saveLatestDateToDisk(state.date)
            session.transferUserInfo([WatchMessageKeys.watchState: message])
            debug(.watchManager, "📤 Transferred new WatchState snapshot via userInfo")
        }
    }

    func sendAcknowledgment(toWatch success: Bool, message: String = "", ackCode: AcknowledgmentCode) {
        guard let session = session, session.isReachable else {
            debug(.watchManager, "⌚️ Watch not reachable for acknowledgment")
            return
        }

        let ackMessage: [String: Any] = [
            WatchMessageKeys.acknowledged: success,
            WatchMessageKeys.message: message,
            WatchMessageKeys.ackCode: ackCode.rawValue
        ]

        session.sendMessage(ackMessage, replyHandler: nil) { error in
            debug(.watchManager, "❌ Error sending acknowledgment: \(error)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            debug(.watchManager, "📱 Phone session activation failed: \(error)")
            return
        }

        debug(.watchManager, "📱 Phone session activated with state: \(activationState.rawValue)")
        debug(.watchManager, "📱 Phone isReachable after activation: \(session.isReachable)")

        // Try to send initial data after activation
        Task {
            let state = await self.setupWatchState()
            await self.sendDataToWatch(state)
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            if let logs = message["watchLogs"] as? String {
                SimpleLogReporter.appendToWatchLog(logs)
            }

            if let requestWatchUpdate = message[WatchMessageKeys.requestWatchUpdate] as? String,
               requestWatchUpdate == WatchMessageKeys.watchState
            {
                debug(.watchManager, "📱 Watch requested watch state data update.")
                guard let self = self else { return }

                Task {
                    let state = await self.setupWatchState()
                    await self.sendDataToWatch(state)
                }
                return
            }

            if let bolusAmount = message[WatchMessageKeys.bolus] as? Double,
               message[WatchMessageKeys.carbs] == nil,
               message[WatchMessageKeys.date] == nil
            {
                debug(.watchManager, "📱 Received bolus request from watch: \(bolusAmount)U")
                self?.handleBolusRequest(Decimal(bolusAmount))
            } else if let carbsAmount = message[WatchMessageKeys.carbs] as? Int,
                      let timestamp = message[WatchMessageKeys.date] as? TimeInterval,
                      message[WatchMessageKeys.bolus] == nil
            {
                let date = Date(timeIntervalSince1970: timestamp)
                debug(.watchManager, "📱 Received carbs request from watch: \(carbsAmount)g at \(date)")
                self?.handleCarbsRequest(carbsAmount, date)
            } else if let bolusAmount = message[WatchMessageKeys.bolus] as? Double,
                      let carbsAmount = message[WatchMessageKeys.carbs] as? Int,
                      let timestamp = message[WatchMessageKeys.date] as? TimeInterval
            {
                let date = Date(timeIntervalSince1970: timestamp)
                debug(
                    .watchManager,
                    "📱 Received meal bolus combo request from watch: \(bolusAmount)U, \(carbsAmount)g at \(date)"
                )
                self?.handleCombinedRequest(bolusAmount: Decimal(bolusAmount), carbsAmount: Decimal(carbsAmount), date: date)
            } else {
                debug(.watchManager, "📱 Invalid or incomplete data received from watch. Received:  \(message)")
                // Acknowledge failure
                self?.sendAcknowledgment(
                    toWatch: false,
                    message: "Error! Invalid or incomplete data received from watch.",
                    ackCode: .genericFailure
                )
            }

            if message[WatchMessageKeys.cancelOverride] as? Bool == true {
                debug(.watchManager, "📱 Received cancel override request from watch")
                self?.handleCancelOverride()
            }

            if let presetName = message[WatchMessageKeys.activateOverride] as? String {
                debug(.watchManager, "📱 Received activate override request from watch for preset: \(presetName)")
                self?.handleActivateOverride(presetName)
            }

            if let presetName = message[WatchMessageKeys.activateTempTarget] as? String {
                debug(.watchManager, "📱 Received activate temp target request from watch for preset: \(presetName)")
                self?.handleActivateTempTarget(presetName)
            }

            if message[WatchMessageKeys.cancelTempTarget] as? Bool == true {
                debug(.watchManager, "📱 Received cancel temp target request from watch")
                self?.handleCancelTempTarget()
            }

            if message[WatchMessageKeys.requestBolusRecommendation] as? Bool == true {
                let carbs = message[WatchMessageKeys.carbs] as? Int ?? 0

                var minPredBG: Decimal = 54

                Task { [weak self] in
                    guard let self = self else { return }

                    do {
                        // Fetch determination data
                        let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                            predicate: NSPredicate.predicateFor30MinAgoForDetermination
                        )
                        let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared.getNSManagedObject(
                            with: determinationIds,
                            context: backgroundContext
                        )

                        await MainActor.run {
                            minPredBG = determinationObjects.first?.minPredBGFromReason ?? 54
                        }

                    } catch let error as CoreDataError {
                        debug(.default, "Core Data error: \(error)")
                    } catch {
                        debug(.default, "Unexpected error: \(error)")
                    }

                    // Get recommendation from BolusCalculationManager
                    let result = await bolusCalculationManager.handleBolusCalculation(
                        carbs: Decimal(carbs),
                        useFattyMealCorrection: false,
                        useSuperBolus: false,
                        lastLoopDate: apsManager.lastLoopDate,
                        minPredBG: minPredBG
                    )

                    // Send recommendation back to watch
                    let recommendationMessage: [String: Any] = [
                        WatchMessageKeys.recommendedBolus: NSDecimalNumber(decimal: result.insulinCalculated)
                    ]

                    if let session = self.session, session.isReachable {
                        debug(.watchManager, "📱 Sending recommendedBolus: \(result.insulinCalculated)")
                        session.sendMessage(recommendationMessage, replyHandler: nil)
                    }
                }
                return
            }
        }
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let logs = userInfo["watchLogs"] as? String {
            SimpleLogReporter.appendToWatchLog(logs)
        }
    }

    #if os(iOS)
        func sessionDidBecomeInactive(_: WCSession) {}
        func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }
    #endif

    func sessionReachabilityDidChange(_ session: WCSession) {
        debug(.watchManager, "📱 Phone reachability changed: \(session.isReachable)")

        if session.isReachable {
            // Try to send data when connection is established
            Task {
                let state = await self.setupWatchState()
                await self.sendDataToWatch(state)
            }
        } else {
            // Try to reconnect after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.retryConnection()
            }
        }
    }

    /// Processes bolus requests received from the Watch
    /// - Parameter amount: The requested bolus amount in units
    private func handleBolusRequest(_ amount: Decimal) {
        Task {
            await apsManager.enactBolus(amount: Double(amount), isSMB: false) { success, message in
                // Acknowledge success or error of bolus
                self.sendAcknowledgment(
                    toWatch: success,
                    message: message,
                    ackCode: success == true ? .genericSuccess : .genericFailure
                )
            }
            debug(.watchManager, "📱 Enacted bolus via APS Manager: \(amount)U")
        }
    }

    /// Handles carbs entry requests received from the Watch
    /// - Parameters:
    ///   - amount: The carbs amount in grams
    ///   - date: Timestamp for the carbs entry
    private func handleCarbsRequest(_ amount: Int, _ date: Date) {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            await context.perform {
                let carbEntry = CarbEntryStored(context: context)
                carbEntry.id = UUID()
                carbEntry.carbs = Double(truncating: amount as NSNumber)
                carbEntry.date = date
                carbEntry.note = String(localized: "Via Watch", comment: "Note added to carb entry when entered via watch")
                carbEntry.isFPU = false // set this to false to ensure watch-entered carbs are displayed in main chart
                carbEntry.isUploadedToNS = false

                do {
                    guard context.hasChanges else {
                        // Acknowledge failure
                        self.sendAcknowledgment(
                            toWatch: false,
                            message: "Error! Something went wrong when processing your request.",
                            ackCode: .genericFailure
                        )
                        return
                    }
                    try context.save()
                    debug(.watchManager, "📱 Saved carbs from watch: \(amount)g at \(date)")

                    // Acknowledge success
                    self.sendAcknowledgment(
                        toWatch: true,
                        message: String(
                            localized: "Carbs logged successfully.",
                            comment: "Success message sent to watch when carbs are logged successfully"
                        ),
                        ackCode: .carbsLogged
                    )
                } catch {
                    debug(.watchManager, "❌ Error saving carbs: \(error)")

                    // Acknowledge failure
                    self.sendAcknowledgment(toWatch: false, message: "Error logging carbs", ackCode: .genericFailure)
                }
            }
        }
    }

    /// Handles combined bolus and carbs entry requests received from the Watch.
    /// - Parameters:
    ///   - bolusAmount: The bolus amount in units
    ///   - carbsAmount: The carbs amount in grams
    ///   - date: Timestamp for the carbs entry
    private func handleCombinedRequest(bolusAmount: Decimal, carbsAmount: Decimal, date: Date) {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            do {
                // Notify Watch: "Saving carbs..."
                self.sendAcknowledgment(
                    toWatch: true,
                    message: String(
                        localized: "Saving Carbs...",
                        comment: "Successful message sent to watch when saving carbs"
                    ),
                    ackCode: .savingCarbs
                )

                // Save carbs entry in Core Data
                try await context.perform {
                    let carbEntry = CarbEntryStored(context: context)
                    carbEntry.id = UUID()
                    carbEntry.carbs = NSDecimalNumber(decimal: carbsAmount).doubleValue
                    carbEntry.date = date
                    carbEntry.note = String(localized: "Via Watch", comment: "Note added to carb entry when entered via watch")
                    carbEntry.isFPU = false // set this to false to ensure watch-entered carbs are displayed in main chart
                    carbEntry.isUploadedToNS = false

                    guard context.hasChanges else {
                        // Acknowledge failure
                        self.sendAcknowledgment(
                            toWatch: false,
                            message: "Error! Something went wrong when processing your request.",
                            ackCode: .genericFailure
                        )
                        return
                    }
                    try context.save()
                    debug(.watchManager, "📱 Saved carbs from watch: \(carbsAmount) g at \(date)")
                }

                // Notify Watch: "Enacting bolus..."
                sendAcknowledgment(
                    toWatch: true,
                    message: String(
                        localized: "Enacting bolus...",
                        comment: "Successful message sent to watch when enacting bolus"
                    ),
                    ackCode: .enactingBolus
                )

                // Enact bolus via APS Manager
                let bolusDouble = NSDecimalNumber(decimal: bolusAmount).doubleValue
                await apsManager.enactBolus(amount: bolusDouble, isSMB: false) { success, message in
                    // Acknowledge success or error of bolus
                    self.sendAcknowledgment(
                        toWatch: success,
                        message: message,
                        ackCode: success == true ? .genericSuccess : .genericFailure
                    )
                }
                debug(.watchManager, "📱 Enacted bolus from watch via APS Manager: \(bolusDouble) U")
                // Notify Watch: "Carbs and bolus logged successfully"
                sendAcknowledgment(
                    toWatch: true,
                    message: String(
                        localized: "Carbs and Bolus logged successfully.",
                        comment: "Successful message sent to watch when logging carbs and bolus"
                    ),
                    ackCode: .comboComplete
                )

            } catch {
                debug(.watchManager, "❌ Error processing combined request: \(error)")
                sendAcknowledgment(toWatch: false, message: "Failed to log carbs and bolus", ackCode: .genericFailure)
            }
        }
    }

    private func handleCancelOverride() {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            if let overrideId = try await overrideStorage.fetchLatestActiveOverride() {
                let override = await context.perform {
                    context.object(with: overrideId) as? OverrideStored
                }

                await context.perform {
                    if let activeOverride = override {
                        activeOverride.enabled = false

                        do {
                            guard context.hasChanges else {
                                // Acknowledge failure
                                self.sendAcknowledgment(
                                    toWatch: false,
                                    message: "Error! Something went wrong when processing your request.",
                                    ackCode: .genericFailure
                                )
                                return
                            }
                            try context.save()
                            debug(.watchManager, "📱 Successfully stopped override")

                            // Send notification to update Adjustments UI
                            Foundation.NotificationCenter.default.post(
                                name: .didUpdateOverrideConfiguration,
                                object: nil
                            )

                            // Acknowledge cancellation success
                            self.sendAcknowledgment(
                                toWatch: true,
                                message: String(
                                    localized: "Stopped Override successfully.",
                                    comment: "Stopped Override successfully"
                                ),
                                ackCode: .overrideStopped
                            )
                        } catch {
                            debug(.watchManager, "❌ Error cancelling override: \(error)")
                            // Acknowledge cancellation error
                            self.sendAcknowledgment(toWatch: false, message: "Error stopping Override.", ackCode: .genericFailure)
                        }
                    }
                }
            } else {
                debug(.watchManager, "❌ No active override found.")
                self.sendAcknowledgment(
                    toWatch: false,
                    message: "No active override found.",
                    ackCode: .genericFailure
                )
                return
            }
        }
    }

    private func handleActivateOverride(_ presetName: String) {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            debug(.watchManager, "📱 Fetching all override presets...")

            // Fetch all presets to find the one to activate
            let presetIds = try await overrideStorage.fetchForOverridePresets()
            let presets: [OverrideStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: presetIds, context: context)

            debug(.watchManager, "📱 Checking for active override...")

            do {
                // Check for active override
                if let activeOverrideId = try await overrideStorage.fetchLatestActiveOverride() {
                    let activeOverride = await context.perform {
                        context.object(with: activeOverrideId) as? OverrideStored
                    }

                    // Deactivate, if necessary
                    if let override = activeOverride {
                        await context.perform {
                            override.enabled = false
                        }
                    }
                } else {
                    debug(.watchManager, "📱 Currently no override is active... proceeding to activate override: \(presetName)")
                }
            } catch {
                debug(.watchManager, "❌ Error while checking for active override: \(error)")
                self.sendAcknowledgment(
                    toWatch: false,
                    message: "Failed to load active override.",
                    ackCode: .genericFailure
                )
                return
            }

            // Activate the selected preset
            await context.perform {
                guard let presetToActivate = presets
                    .first(where: { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) == presetName })
                else {
                    debug(.watchManager, "❌ No matching preset found for name: \"\(presetName)\" in \(presets.map(\.name))")
                    self.sendAcknowledgment(
                        toWatch: false,
                        message: String(
                            localized: "Preset \"\(presetName)\" not found.",
                            comment: "Preset not found"
                        ),
                        ackCode: .genericFailure
                    )
                    return
                }

                presetToActivate.enabled = true
                presetToActivate.date = Date()

                do {
                    guard context.hasChanges else {
                        // Acknowledge failure
                        self.sendAcknowledgment(
                            toWatch: false,
                            message: String(
                                localized: "Error! Something went wrong when processing your request.",
                                comment: "Error message when activating override"
                            ),
                            ackCode: .genericFailure
                        )
                        return
                    }
                    try context.save()
                    debug(.watchManager, "📱 Successfully activated override: \(presetName)")

                    // Send notification to update Adjustments UI
                    Foundation.NotificationCenter.default.post(
                        name: .didUpdateOverrideConfiguration,
                        object: nil
                    )

                    // Acknowledge activation success
                    self.sendAcknowledgment(
                        toWatch: true,
                        message: String(
                            localized: "Started Override \"\(presetName)\" successfully.",
                            comment: "Start override with override name"
                        ),
                        ackCode: .overrideStarted
                    )
                } catch {
                    debug(.watchManager, "❌ Error activating override: \(error)")
                    // Acknowledge activation error
                    self.sendAcknowledgment(
                        toWatch: false,
                        message: "Error activating Override \"\(presetName)\".",
                        ackCode: .genericFailure
                    )
                }
            }
        }
    }

    private func handleActivateTempTarget(_ presetName: String) {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            // Fetch all presets to find the one to activate
            let presetIds = try await tempTargetStorage.fetchForTempTargetPresets()
            let presets: [TempTargetStored] = try await CoreDataStack.shared
                .getNSManagedObject(with: presetIds, context: context)

            // Check for active temp target
            if let activeTempTargetId = try await tempTargetStorage.loadLatestTempTargetConfigurations(fetchLimit: 1).first {
                let activeTempTarget = await context.perform {
                    context.object(with: activeTempTargetId) as? TempTargetStored
                }

                // Deactivate if exists
                if let tempTarget = activeTempTarget {
                    await context.perform {
                        tempTarget.enabled = false
                    }
                }
            }

            // Activate the selected preset
            await context.perform {
                if let presetToActivate = presets.first(where: { $0.name == presetName }) {
                    presetToActivate.enabled = true
                    presetToActivate.date = Date()

                    do {
                        guard context.hasChanges else {
                            // Acknowledge failure
                            self.sendAcknowledgment(
                                toWatch: false,
                                message: "Error! Something went wrong when processing your request.",
                                ackCode: .genericFailure
                            )
                            return
                        }
                        try context.save()
                        debug(.watchManager, "📱 Successfully activated temp target: \(presetName)")

                        let settingsHalfBasalTarget = self.settingsManager.preferences
                            .halfBasalExerciseTarget

                        let halfBasalTarget = presetToActivate.halfBasalTarget?.decimalValue

                        // To activate the temp target also in oref
                        let tempTarget = TempTarget(
                            name: presetToActivate.name,
                            createdAt: Date(),
                            targetTop: presetToActivate.target?.decimalValue,
                            targetBottom: presetToActivate.target?.decimalValue,
                            duration: presetToActivate.duration?.decimalValue ?? 0,
                            enteredBy: TempTarget.local,
                            reason: TempTarget.custom,
                            isPreset: true,
                            enabled: true,
                            halfBasalTarget: halfBasalTarget ?? settingsHalfBasalTarget
                        )

                        self.tempTargetStorage.saveTempTargetsToStorage([tempTarget])

                        // Send notification to update Adjustments UI
                        Foundation.NotificationCenter.default.post(
                            name: .didUpdateTempTargetConfiguration,
                            object: nil
                        )

                        // Acknowledge activation success
                        self.sendAcknowledgment(
                            toWatch: true,
                            message: String(
                                localized: "Started Temp Target \"\(presetName)\" successfully.",
                                comment: "Started Temp Target successfully."
                            ),
                            ackCode: .tempTargetStarted
                        )
                    } catch {
                        debug(.watchManager, "❌ Error activating temp target: \(error)")
                        // Acknowledge activation error
                        self.sendAcknowledgment(
                            toWatch: false,
                            message: "Error activating Temp Target \"\(presetName)\".",
                            ackCode: .genericFailure
                        )
                    }
                }
            }
        }
    }

    private func handleCancelTempTarget() {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            if let tempTargetId = try await tempTargetStorage.loadLatestTempTargetConfigurations(fetchLimit: 1).first {
                let tempTarget = await context.perform {
                    context.object(with: tempTargetId) as? TempTargetStored
                }

                await context.perform {
                    if let activeTempTarget = tempTarget {
                        activeTempTarget.enabled = false

                        do {
                            guard context.hasChanges else {
                                // Acknowledge failure
                                self.sendAcknowledgment(
                                    toWatch: false,
                                    message: "Error! Something went wrong when processing your request.",
                                    ackCode: .genericFailure
                                )
                                return
                            }
                            try context.save()
                            debug(.watchManager, "📱 Successfully cancelled temp target")

                            // To cancel the temp target also for oref
                            self.tempTargetStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date())])

                            // Send notification to update Adjustments UI
                            Foundation.NotificationCenter.default.post(
                                name: .didUpdateTempTargetConfiguration,
                                object: nil
                            )

                            // Acknowledge cancellation success
                            self.sendAcknowledgment(
                                toWatch: true,
                                message: String(
                                    localized: "Stopped Temp Target successfully.",
                                    comment: "Stopped Temp Target successfully."
                                ),
                                ackCode: .tempTargetStopped
                            )
                        } catch {
                            debug(.watchManager, "❌ Error stopping temp target: \(error)")
                            // Acknowledge cancellation error
                            self.sendAcknowledgment(
                                toWatch: false,
                                message: "Error stopping Temp Target.",
                                ackCode: .genericFailure
                            )
                        }
                    }
                }
            }
        }
    }
}

// TODO: - is there a better approach than setting up the watch state every time a setting has changed?
extension BaseWatchManager: SettingsObserver, PumpSettingsObserver {
    // to update maxBolus
    func pumpSettingsDidChange(_: PumpSettings) {
        Task {
            let state = await self.setupWatchState()
            await self.sendDataToWatch(state)
        }
    }

    // to update the rest
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
        glucoseColorScheme = settingsManager.settings.glucoseColorScheme
        lowGlucose = settingsManager.settings.low
        highGlucose = settingsManager.settings.high

        Task {
            let state = await self.setupWatchState()
            await self.sendDataToWatch(state)
        }
    }
}

extension BaseWatchManager {
    /// Retrieves the current glucose target based on the time of day.
    private func getCurrentGlucoseTarget() async -> Decimal? {
        let now = Date()
        let calendar = Calendar.current

        let bgTargets = await fileStorage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
            ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
            ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
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
                return entry.value
            }
        }

        return nil
    }
}

extension BaseWatchManager {
    enum AcknowledgmentCode: String, Codable {
        case savingCarbs = "saving_carbs"
        case enactingBolus = "enacting_bolus"
        case comboComplete = "combo_complete"
        case carbsLogged = "carbs_logged"
        case overrideStarted = "override_started"
        case overrideStopped = "override_stopped"
        case tempTargetStarted = "temp_target_started"
        case tempTargetStopped = "temp_target_stopped"
        case genericSuccess = "success"
        case genericFailure = "failure"
    }
}
