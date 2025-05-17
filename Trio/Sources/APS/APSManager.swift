import Combine
import CoreData
import Foundation
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject

protocol APSManager {
    func heartbeat(date: Date)
    func enactBolus(amount: Double, isSMB: Bool, callback: ((Bool, String) -> Void)?) async
    var pumpManager: PumpManagerUI? { get set }
    var bluetoothManager: BluetoothStateManager? { get }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var isLooping: CurrentValueSubject<Bool, Never> { get }
    var lastLoopDate: Date { get }
    var lastLoopDateSubject: PassthroughSubject<Date, Never> { get }
    var bolusProgress: CurrentValueSubject<Decimal?, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
    var isManualTempBasal: Bool { get }
    func enactTempBasal(rate: Double, duration: TimeInterval) async
    func determineBasal() async throws
    func determineBasalSync() async throws
    func simulateDetermineBasal(simulatedCarbsAmount: Decimal, simulatedBolusAmount: Decimal) async -> Determination?
    func roundBolus(amount: Decimal) -> Decimal
    var lastError: CurrentValueSubject<Error?, Never> { get }
    func cancelBolus(_ callback: ((Bool, String) -> Void)?) async
}

enum APSError: LocalizedError {
    case pumpError(Error)
    case invalidPumpState(message: String)
    case glucoseError(message: String)
    case apsError(message: String)
    case manualBasalTemp(message: String)

    var errorDescription: String? {
        switch self {
        case let .pumpError(error):
            return String(localized: "Pump Error (\(error.localizedDescription)).")
        case let .invalidPumpState(message):
            return String(localized: "Invalid Pump State (\(message)).")
        case let .glucoseError(message):
            return String(localized: "Invalid Glucose (\(message)).")
        case let .apsError(message):
            return String(localized: "Invalid Algorithm Response (\(message)).")
        case let .manualBasalTemp(message):
            return String(localized: "Manual Temporary Basal Rate (\(message)). Looping suspended.")
        }
    }

    static func pumpErrorMatches(message: String) -> Bool {
        message.contains(String(localized: "Pump Error"))
    }

    static func pumpWarningMatches(message: String) -> Bool {
        message.contains(String(localized: "Invalid Pump State")) || message
            .contains("PumpMessage") || message
            .contains("PumpOpsError") || message.contains("RileyLink") || message
            .contains(String(localized: "Pump did not respond in time"))
    }
}

final class BaseAPSManager: APSManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseAPSManager.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var alertHistoryStorage: AlertHistoryStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var determinationStorage: DeterminationStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var nightscout: NightscoutManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var tddStorage: TDDStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Persisted(key: "lastLoopStartDate") private var lastLoopStartDate: Date = .distantPast
    @Persisted(key: "lastLoopDate") var lastLoopDate: Date = .distantPast {
        didSet {
            lastLoopDateSubject.send(lastLoopDate)
        }
    }

    let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    let privateContext = CoreDataStack.shared.newTaskContext()

    private var openAPS: OpenAPS!

    private var lifetime = Lifetime()

    private var backgroundTaskID: UIBackgroundTaskIdentifier?

    var pumpManager: PumpManagerUI? {
        get { deviceDataManager.pumpManager }
        set { deviceDataManager.pumpManager = newValue }
    }

    var bluetoothManager: BluetoothStateManager? { deviceDataManager.bluetoothManager }

    @Persisted(key: "isManualTempBasal") var isManualTempBasal: Bool = false

    let isLooping = CurrentValueSubject<Bool, Never>(false)
    let lastLoopDateSubject = PassthroughSubject<Date, Never>()
    let lastError = CurrentValueSubject<Error?, Never>(nil)

    let bolusProgress = CurrentValueSubject<Decimal?, Never>(nil)

    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> {
        deviceDataManager.pumpDisplayState
    }

    var pumpName: CurrentValueSubject<String, Never> {
        deviceDataManager.pumpName
    }

    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> {
        deviceDataManager.pumpExpiresAtDate
    }

    var settings: TrioSettings {
        get { settingsManager.settings }
        set { settingsManager.settings = newValue }
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: storage, tddStorage: tddStorage)
        subscribe()
        lastLoopDateSubject.send(lastLoopDate)

        isLooping
            .weakAssign(to: \.deviceDataManager.loopInProgress, on: self)
            .store(in: &lifetime)
    }

    private func subscribe() {
        if settingsManager.settings.units == .mmolL {
            let wasParsed = storage.parseOnFileSettingsToMgdL()
            if wasParsed {
                Task {
                    do {
                        try await openAPS.createProfiles()
                    } catch {
                        debug(
                            .apsManager,
                            "\(DebuggingIdentifiers.failed) Error creating profiles: \(error)"
                        )
                    }
                }
            }
        }

        deviceDataManager.recommendsLoop
            .receive(on: processQueue)
            .sink { [weak self] in
                self?.loop()
            }
            .store(in: &lifetime)
        pumpManager?.addStatusObserver(self, queue: processQueue)

        deviceDataManager.errorSubject
            .receive(on: processQueue)
            .map { APSError.pumpError($0) }
            .sink {
                self.processError($0)
            }
            .store(in: &lifetime)

        deviceDataManager.bolusTrigger
            .receive(on: processQueue)
            .sink { bolusing in
                if bolusing {
                    self.createBolusReporter()
                } else {
                    self.clearBolusReporter()
                }
            }
            .store(in: &lifetime)

        // manage a manual Temp Basal from OmniPod - Force loop() after stop a temp basal or finished
        deviceDataManager.manualTempBasal
            .receive(on: processQueue)
            .sink { manualBasal in
                if manualBasal {
                    self.isManualTempBasal = true
                } else {
                    if self.isManualTempBasal {
                        self.isManualTempBasal = false
                        self.loop()
                    }
                }
            }
            .store(in: &lifetime)
    }

    func heartbeat(date: Date) {
        deviceDataManager.heartbeat(date: date)
    }

    // Loop entry point
    private func loop() {
        Task { [weak self] in
            guard let self else { return }

            // Check if we can start a new loop
            guard await self.canStartNewLoop() else { return }

            // Setup loop and background task
            var (loopStatRecord, backgroundTask) = await self.setupLoop()

            do {
                // Execute loop logic
                try await self.executeLoop(loopStatRecord: &loopStatRecord)

                // Upload data to Nightscout if available
                if let nightscoutManager = self.nightscout {
                    await nightscoutManager.uploadCarbs()
                    await nightscoutManager.uploadPumpHistory()
                    await nightscoutManager.uploadOverrides()
                    await nightscoutManager.uploadTempTargets()
                }
            } catch {
                var updatedStats = loopStatRecord
                updatedStats.end = Date()
                updatedStats.duration = roundDouble((updatedStats.end! - updatedStats.start).timeInterval / 60, 2)
                updatedStats.loopStatus = error.localizedDescription
                await loopCompleted(error: error, loopStatRecord: updatedStats)
                debug(.apsManager, "\(DebuggingIdentifiers.failed) Failed to complete Loop: \(error)")
            }

            // Cleanup background task
            if let backgroundTask = backgroundTask {
                await UIApplication.shared.endBackgroundTask(backgroundTask)
                self.backgroundTaskID = .invalid
            }
        }
    }

    private func canStartNewLoop() async -> Bool {
        // Check if too soon for next loop
        if lastLoopDate > lastLoopStartDate {
            guard lastLoopStartDate.addingTimeInterval(Config.loopInterval) < Date() else {
                debug(.apsManager, "Not enough time have passed since last loop at : \(lastLoopStartDate)")
                return false
            }
        }

        // Check if loop already in progress
        guard !isLooping.value else {
            warning(.apsManager, "Loop already in progress. Skip recommendation.")
            return false
        }

        return true
    }

    private func setupLoop() async -> (LoopStats, UIBackgroundTaskIdentifier?) {
        // Start background task
        let backgroundTask = await UIApplication.shared.beginBackgroundTask(withName: "Loop starting") { [weak self] in
            guard let self, let backgroundTask = self.backgroundTaskID else { return }
            Task {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            self.backgroundTaskID = .invalid
        }
        backgroundTaskID = backgroundTask

        // Set loop start time
        lastLoopStartDate = Date()

        // Calculate interval from previous loop
        let interval = await calculateLoopInterval()

        // Create initial loop stats record
        let loopStatRecord = LoopStats(
            start: lastLoopStartDate,
            loopStatus: "Starting",
            interval: interval
        )

        isLooping.send(true)

        return (loopStatRecord, backgroundTask)
    }

    private func executeLoop(loopStatRecord: inout LoopStats) async throws {
        try await determineBasal()

        // Handle open loop
        guard settings.closedLoop else {
            loopStatRecord.end = Date()
            loopStatRecord.duration = roundDouble((loopStatRecord.end! - loopStatRecord.start).timeInterval / 60, 2)
            loopStatRecord.loopStatus = "Success"
            await loopCompleted(loopStatRecord: loopStatRecord)
            return
        }

        // Handle closed loop
        try await enactDetermination()
        loopStatRecord.end = Date()
        loopStatRecord.duration = roundDouble((loopStatRecord.end! - loopStatRecord.start).timeInterval / 60, 2)
        loopStatRecord.loopStatus = "Success"
        await loopCompleted(loopStatRecord: loopStatRecord)
    }

    private func calculateLoopInterval() async -> Double? {
        do {
            return try await privateContext.perform {
                let requestStats = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
                let sortStats = NSSortDescriptor(key: "end", ascending: false)
                requestStats.sortDescriptors = [sortStats]
                requestStats.fetchLimit = 1
                let previousLoop = try self.privateContext.fetch(requestStats)

                if (previousLoop.first?.end ?? .distantFuture) < self.lastLoopStartDate {
                    return self.roundDouble(
                        (self.lastLoopStartDate - (previousLoop.first?.end ?? Date())).timeInterval / 60,
                        1
                    )
                }
                return nil
            }
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch the last loop with error: \(error)")
            return nil
        }
    }

    // Loop exit point
    private func loopCompleted(error: Error? = nil, loopStatRecord: LoopStats) async {
        isLooping.send(false)

        if let error = error {
            warning(.apsManager, "Loop failed with error: \(error)")
            if let backgroundTask = backgroundTaskID {
                await UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTaskID = .invalid
            }
            processError(error)
        } else {
            debug(.apsManager, "Loop succeeded")
            lastLoopDate = Date()
            lastError.send(nil)
        }

        loopStats(loopStatRecord: loopStatRecord)

        if settings.closedLoop {
            await reportEnacted(wasEnacted: error == nil)
        }

        // End of the BG tasks
        if let backgroundTask = backgroundTaskID {
            await UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTaskID = .invalid
        }
    }

    private func verifyStatus() -> Error? {
        guard let pump = pumpManager else {
            return APSError.invalidPumpState(message: String(localized: "Pump not set"))
        }
        let status = pump.status.pumpStatus

        guard !status.bolusing else {
            return APSError.invalidPumpState(message: String(localized: "Pump is bolusing"))
        }

        guard !status.suspended else {
            return APSError.invalidPumpState(message: String(localized: "Pump suspended"))
        }

        let reservoir = storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self) ?? 100
        guard reservoir >= 0 else {
            return APSError.invalidPumpState(message: String(localized: "Reservoir is empty"))
        }

        return nil
    }

    func autosense() async throws -> Bool {
        guard let autosense = await storage.retrieveAsync(OpenAPS.Settings.autosense, as: Autosens.self),
              (autosense.timestamp ?? .distantPast).addingTimeInterval(30.minutes.timeInterval) > Date()
        else {
            let result = try await openAPS.autosense()
            return result != nil
        }

        return false
    }

    /// Calculates and stores the Total Daily Dose (TDD)
    private func calculateAndStoreTDD() async throws {
        guard let pumpManager else { return }

        async let pumpHistory = pumpHistoryStorage.getPumpHistory()
        async let basalProfile = storage
            .retrieveAsync(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ??
            [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile)) ??
            [] // OpenAPS.defaults ensures we at least get default rate of 1u/hr for 24 hrs

        // Calculate TDD
        let tddResult = try await tddStorage.calculateTDD(
            pumpManager: pumpManager,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile
        )

        // Store TDD in Core Data
        await tddStorage.storeTDD(tddResult)
    }

    func determineBasal() async throws {
        debug(.apsManager, "Start determine basal")

        try await calculateAndStoreTDD()

        // Fetch glucose asynchronously
        let glucose = try await fetchGlucose(predicate: NSPredicate.predicateForOneHourAgo, fetchLimit: 6)

        // Perform the context-related checks and actions
        let isValidGlucoseData = await privateContext.perform { [weak self] in
            guard let self else { return false }

            guard glucose.count > 2 else {
                debug(.apsManager, "Not enough glucose data")
                self.processError(APSError.glucoseError(message: String(localized: "Not enough glucose data")))
                return false
            }

            let dateOfLastGlucose = glucose.first?.date
            guard dateOfLastGlucose ?? Date() >= Date().addingTimeInterval(-12.minutes.timeInterval) else {
                debug(.apsManager, "Glucose data is stale")
                self.processError(APSError.glucoseError(message: String(localized: "Glucose data is stale")))
                return false
            }

            guard !GlucoseStored.glucoseIsFlat(glucose) else {
                debug(.apsManager, "Glucose data is too flat")
                self.processError(APSError.glucoseError(message: String(localized: "Glucose data is too flat")))
                return false
            }

            return true
        }

        guard isValidGlucoseData else {
            debug(.apsManager, "Glucose validation failed")
            processError(APSError.glucoseError(message: "Glucose validation failed"))
            return
        }

        do {
            let now = Date()

            // Parallelize the fetches using async let
            async let currentTemp = fetchCurrentTempBasal(date: now)
            async let autosenseResult = autosense()

            _ = try await autosenseResult
            try await openAPS.createProfiles()
            let determination = try await openAPS.determineBasal(currentTemp: await currentTemp, clock: now)

            if let determination = determination {
                // Capture weak self in closure
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.broadcaster.notify(DeterminationObserver.self, on: .main) {
                        $0.determinationDidUpdate(determination)
                    }
                }
            }
        } catch {
            throw APSError.apsError(message: "Error determining basal: \(error.localizedDescription)")
        }
    }

    func determineBasalSync() async throws {
        _ = try await determineBasal()
    }

    func simulateDetermineBasal(simulatedCarbsAmount: Decimal, simulatedBolusAmount: Decimal) async -> Determination? {
        do {
            let temp = try await fetchCurrentTempBasal(date: Date.now)
            return try await openAPS.determineBasal(
                currentTemp: temp,
                clock: Date(),
                simulatedCarbsAmount: simulatedCarbsAmount,
                simulatedBolusAmount: simulatedBolusAmount,
                simulation: true
            )
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Error occurred in invokeDummyDetermineBasalSync: \(error)"
            )
            return nil
        }
    }

    func roundBolus(amount: Decimal) -> Decimal {
        guard let pump = pumpManager else { return amount }
        let rounded = Decimal(pump.roundToSupportedBolusVolume(units: Double(amount)))
        let maxBolus = Decimal(pump.roundToSupportedBolusVolume(units: Double(settingsManager.pumpSettings.maxBolus)))
        return min(rounded, maxBolus)
    }

    private var bolusReporter: DoseProgressReporter?

    func enactBolus(amount: Double, isSMB: Bool, callback: ((Bool, String) -> Void)?) async {
        if amount <= 0 {
            return
        }

        if let error = verifyStatus() {
            processError(error)
            // Capture broadcaster and queue before async context
            let broadcaster = self.broadcaster
            Task { @MainActor in
                broadcaster?.notify(BolusFailureObserver.self, on: .main) {
                    $0.bolusDidFail()
                }
            }
            callback?(false, String(localized: "Error! Failed to enact bolus.", comment: "Error message for enacting a bolus"))
            return
        }

        guard let pump = pumpManager else {
            callback?(false, String(localized: "Error! Failed to enact bolus.", comment: "Error message for enacting a bolus"))
            return
        }

        let roundedAmount = pump.roundToSupportedBolusVolume(units: amount)

        debug(.apsManager, "Enact bolus \(roundedAmount), manual \(!isSMB)")

        do {
            try await pump.enactBolus(units: roundedAmount, automatic: isSMB)
            debug(.apsManager, "Bolus succeeded")
            if !isSMB {
                try await determineBasalSync()
            }
            bolusProgress.send(0)
            callback?(true, String(localized: "Bolus enacted successfully.", comment: "Success message for enacting a bolus"))
        } catch {
            warning(.apsManager, "Bolus failed with error: \(error)")
            processError(APSError.pumpError(error))
            if !isSMB {
                // Use MainActor to handle broadcaster notification
                let broadcaster = self.broadcaster
                Task { @MainActor in
                    broadcaster?.notify(BolusFailureObserver.self, on: .main) {
                        $0.bolusDidFail()
                    }
                }
            }
            callback?(
                false,
                String(localized: "Error! Bolus failed with error: \(error.localizedDescription)")
            )
        }
    }

    func cancelBolus(_ callback: ((Bool, String) -> Void)?) async {
        guard let pump = pumpManager, pump.status.pumpStatus.bolusing else { return }
        debug(.apsManager, "Cancel bolus")
        do {
            _ = try await pump.cancelBolus()
            debug(.apsManager, "Bolus cancelled")
            callback?(true, String(localized: "Bolus cancelled successfully.", comment: "Success message for canceling a bolus"))
        } catch {
            debug(.apsManager, "Bolus cancellation failed with error: \(error)")
            processError(APSError.pumpError(error))
            callback?(
                false,
                String(
                    localized: "Error! Bolus cancellation failed with error: \(error.localizedDescription)",
                    comment: "Error message for canceling a bolus"
                )
            )
        }
        bolusReporter?.removeObserver(self)
        bolusReporter = nil
        bolusProgress.send(nil)
    }

    func enactTempBasal(rate: Double, duration: TimeInterval) async {
        if let error = verifyStatus() {
            processError(error)
            return
        }

        guard let pump = pumpManager else { return }

        // unable to do temp basal during manual temp basal 😁
        if isManualTempBasal {
            processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
            return
        }

        debug(.apsManager, "Enact temp basal \(rate) - \(duration)")

        let roundedAmout = pump.roundToSupportedBasalRate(unitsPerHour: rate)

        do {
            try await pump.enactTempBasal(unitsPerHour: roundedAmout, for: duration)
            debug(.apsManager, "Temp Basal succeeded")
        } catch {
            debug(.apsManager, "Temp Basal failed with error: \(error)")
            processError(APSError.pumpError(error))
        }
    }

    private func fetchCurrentTempBasal(date: Date) async throws -> TempBasal {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: privateContext,
            predicate: NSPredicate.recentPumpHistory,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        let fetchedTempBasal = await privateContext.perform {
            guard let fetchedResults = results as? [PumpEventStored],
                  let tempBasalEvent = fetchedResults.first,
                  let tempBasal = tempBasalEvent.tempBasal,
                  let eventTimestamp = tempBasalEvent.timestamp
            else {
                return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: date)
            }

            let delta = Int((date.timeIntervalSince1970 - eventTimestamp.timeIntervalSince1970) / 60)
            let duration = max(0, Int(tempBasal.duration) - delta)
            let rate = tempBasal.rate as? Decimal ?? 0
            return TempBasal(duration: duration, rate: rate, temp: .absolute, timestamp: date)
        }

        guard let state = pumpManager?.status.basalDeliveryState else { return fetchedTempBasal }

        switch state {
        case .active:
            return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: date)
        case let .tempBasal(dose):
            let rate = Decimal(dose.unitsPerHour)
            let durationMin = max(0, Int((dose.endDate.timeIntervalSince1970 - date.timeIntervalSince1970) / 60))
            return TempBasal(duration: durationMin, rate: rate, temp: .absolute, timestamp: date)
        default:
            return fetchedTempBasal
        }
    }

    private func enactDetermination() async throws {
        guard let determinationID = try await determinationStorage
            .fetchLastDeterminationObjectID(predicate: NSPredicate.predicateFor30MinAgoForDetermination).first
        else {
            throw APSError.apsError(message: "Determination not found")
        }

        guard let pump = pumpManager else {
            throw APSError.apsError(message: "Pump not set")
        }

        // Unable to do temp basal during manual temp basal 😁
        if isManualTempBasal {
            throw APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp")
        }

        let (rateDecimal, durationInSeconds, smbToDeliver) = try await setValues(determinationID: determinationID)

        if let rate = rateDecimal, let duration = durationInSeconds {
            try await performBasal(pump: pump, rate: rate, duration: duration)
        }

        // only perform a bolus if smbToDeliver is > 0
        if let smb = smbToDeliver, smb.compare(NSDecimalNumber(value: 0)) == .orderedDescending {
            try await performBolus(pump: pump, smbToDeliver: smb)
        }
    }

    private func setValues(determinationID: NSManagedObjectID) async throws
        -> (NSDecimalNumber?, TimeInterval?, NSDecimalNumber?)
    {
        return try await privateContext.perform {
            do {
                let determination = try self.privateContext.existingObject(with: determinationID) as? OrefDetermination

                let rate = determination?.rate
                let duration = determination?.duration.flatMap { TimeInterval(truncating: $0) * 60 }
                let smbToDeliver = determination?.smbToDeliver ?? 0

                return (rate, duration, smbToDeliver)
            } catch {
                throw error
            }
        }
    }

    private func performBasal(pump: PumpManager, rate: NSDecimalNumber, duration: TimeInterval) async throws {
        try await pump.enactTempBasal(unitsPerHour: Double(truncating: rate), for: duration)
    }

    private func performBolus(pump: PumpManager, smbToDeliver: NSDecimalNumber) async throws {
        try await pump.enactBolus(units: Double(truncating: smbToDeliver), automatic: true)
        bolusProgress.send(0)
    }

    private func reportEnacted(wasEnacted: Bool) async {
        do {
            guard let determinationID = try await determinationStorage
                .fetchLastDeterminationObjectID(predicate: NSPredicate.predicateFor30MinAgoForDetermination).first
            else {
                debug(.apsManager, "No determination found to report enacted status")
                return
            }

            try await privateContext.perform {
                guard let determinationUpdated = try self.privateContext
                    .existingObject(with: determinationID) as? OrefDetermination
                else {
                    debug(.apsManager, "Could not find determination object in context")
                    return
                }

                determinationUpdated.timestamp = Date()
                determinationUpdated.enacted = wasEnacted
                determinationUpdated.isUploadedToNS = false

                guard self.privateContext.hasChanges else { return }
                try self.privateContext.save()
                debug(.apsManager, "Determination enacted. Enacted: \(wasEnacted)")
            }
        } catch {
            debug(
                .apsManager,
                "\(DebuggingIdentifiers.failed) Error reporting enacted status: \(error)"
            )
        }
    }

    private func roundDecimal(_ decimal: Decimal, _ digits: Double) -> Decimal {
        let rounded = round(Double(decimal) * pow(10, digits)) / pow(10, digits)
        return Decimal(rounded)
    }

    private func roundDouble(_ double: Double, _ digits: Double) -> Double {
        let rounded = round(Double(double) * pow(10, digits)) / pow(10, digits)
        return rounded
    }

    private func medianCalculationDouble(array: [Double]) -> Double {
        guard !array.isEmpty else {
            return 0
        }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    private func medianCalculation(array: [Int]) -> Double {
        guard !array.isEmpty else {
            return 0
        }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return Double((sorted[length / 2 - 1] + sorted[length / 2]) / 2)
        }
        return Double(sorted[length / 2])
    }

    private func tir(_ glucose: [GlucoseStored]) -> (TIR: Double, hypos: Double, hypers: Double, normal_: Double) {
        privateContext.perform {
            let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
            let totalReadings = justGlucoseArray.count
            let highLimit = settingsManager.settings.high
            let lowLimit = settingsManager.settings.low
            let hyperArray = glucose.filter({ $0.glucose >= Int(highLimit) })
            let hyperReadings = hyperArray.compactMap({ each in each.glucose as Int16 }).count
            let hyperPercentage = Double(hyperReadings) / Double(totalReadings) * 100
            let hypoArray = glucose.filter({ $0.glucose <= Int(lowLimit) })
            let hypoReadings = hypoArray.compactMap({ each in each.glucose as Int16 }).count
            let hypoPercentage = Double(hypoReadings) / Double(totalReadings) * 100
            // Euglyccemic range
            let normalArray = glucose.filter({ $0.glucose >= 70 && $0.glucose <= 140 })
            let normalReadings = normalArray.compactMap({ each in each.glucose as Int16 }).count
            let normalPercentage = Double(normalReadings) / Double(totalReadings) * 100
            // TIR
            let tir = 100 - (hypoPercentage + hyperPercentage)
            return (
                roundDouble(tir, 1),
                roundDouble(hypoPercentage, 1),
                roundDouble(hyperPercentage, 1),
                roundDouble(normalPercentage, 1)
            )
        }
    }

    private func glucoseStats(_ fetchedGlucose: [GlucoseStored])
        -> (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double)
    {
        let glucose = fetchedGlucose
        // First date
        let last = glucose.last?.date ?? Date()
        // Last date (recent)
        let first = glucose.first?.date ?? Date()
        // Total time in days
        let numberOfDays = (first - last).timeInterval / 8.64E4
        let denominator = numberOfDays < 1 ? 1 : numberOfDays
        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let sumReadings = justGlucoseArray.reduce(0, +)
        let countReadings = justGlucoseArray.count
        let glucoseAverage = Double(sumReadings) / Double(countReadings)
        let medianGlucose = medianCalculation(array: justGlucoseArray)
        var NGSPa1CStatisticValue = 0.0
        var IFCCa1CStatisticValue = 0.0

        NGSPa1CStatisticValue = (glucoseAverage + 46.7) / 28.7 // NGSP (%)
        IFCCa1CStatisticValue = 10.929 *
            (NGSPa1CStatisticValue - 2.152) // IFCC (mmol/mol)  A1C(mmol/mol) = 10.929 * (A1C(%) - 2.15)
        var sumOfSquares = 0.0

        for array in justGlucoseArray {
            sumOfSquares += pow(Double(array) - Double(glucoseAverage), 2)
        }
        var sd = 0.0
        var cv = 0.0
        // Avoid division by zero
        if glucoseAverage > 0 {
            sd = sqrt(sumOfSquares / Double(countReadings))
            cv = sd / Double(glucoseAverage) * 100
        }
        let conversionFactor = 0.0555
        let units = settingsManager.settings.units

        var output: (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double)
        output = (
            ifcc: IFCCa1CStatisticValue,
            ngsp: NGSPa1CStatisticValue,
            average: glucoseAverage * (units == .mmolL ? conversionFactor : 1),
            median: medianGlucose * (units == .mmolL ? conversionFactor : 1),
            sd: sd * (units == .mmolL ? conversionFactor : 1), cv: cv,
            readings: Double(countReadings) / denominator
        )
        return output
    }

    private func loops(_ fetchedLoops: [LoopStatRecord]) -> Loops {
        let loops = fetchedLoops
        // First date
        let previous = loops.last?.end ?? Date()
        // Last date (recent)
        let current = loops.first?.start ?? Date()
        // Total time in days
        let totalTime = (current - previous).timeInterval / 8.64E4
        //
        let durationArray = loops.compactMap({ each in each.duration })
        let durationArrayCount = durationArray.count
        let durationAverage = durationArray.reduce(0, +) / Double(durationArrayCount) * 60
        let medianDuration = medianCalculationDouble(array: durationArray) * 60
        let max_duration = (durationArray.max() ?? 0) * 60
        let min_duration = (durationArray.min() ?? 0) * 60
        let successsNR = loops.compactMap({ each in each.loopStatus }).filter({ each in each!.contains("Success") }).count
        let errorNR = durationArrayCount - successsNR
        let total = Double(successsNR + errorNR) == 0 ? 1 : Double(successsNR + errorNR)
        let successRate: Double? = (Double(successsNR) / total) * 100
        let loopNr = totalTime <= 1 ? total : round(total / (totalTime != 0 ? totalTime : 1))
        let intervalArray = loops.compactMap({ each in each.interval as Double })
        let count = intervalArray.count != 0 ? intervalArray.count : 1
        let median_interval = medianCalculationDouble(array: intervalArray)
        let intervalAverage = intervalArray.reduce(0, +) / Double(count)
        let maximumInterval = intervalArray.max()
        let minimumInterval = intervalArray.min()
        //
        let output = Loops(
            loops: Int(loopNr),
            errors: errorNR,
            success_rate: roundDecimal(Decimal(successRate ?? 0), 1),
            avg_interval: roundDecimal(Decimal(intervalAverage), 1),
            median_interval: roundDecimal(Decimal(median_interval), 1),
            min_interval: roundDecimal(Decimal(minimumInterval ?? 0), 1),
            max_interval: roundDecimal(Decimal(maximumInterval ?? 0), 1),
            avg_duration: roundDecimal(Decimal(durationAverage), 1),
            median_duration: roundDecimal(Decimal(medianDuration), 1),
            min_duration: roundDecimal(Decimal(min_duration), 1),
            max_duration: roundDecimal(Decimal(max_duration), 1)
        )
        return output
    }

    // fetch glucose for time interval
    func fetchGlucose(predicate: NSPredicate, fetchLimit: Int? = nil, batchSize: Int? = nil) async throws -> [GlucoseStored] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: privateContext,
            predicate: predicate,
            key: "date",
            ascending: false,
            fetchLimit: fetchLimit,
            batchSize: batchSize
        )

        return try await privateContext.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return glucoseResults
        }
    }

    private func lastLoopForStats() async -> Date? {
        let requestStats = StatsData.fetchRequest() as NSFetchRequest<StatsData>
        let sortStats = NSSortDescriptor(key: "lastrun", ascending: false)
        requestStats.sortDescriptors = [sortStats]
        requestStats.fetchLimit = 1

        return await privateContext.perform {
            do {
                return try self.privateContext.fetch(requestStats).first?.lastrun
            } catch {
                print(error.localizedDescription)
                return .distantPast
            }
        }
    }

    private func loopStats(oneDayGlucose: Double) async -> LoopCycles {
        let requestLSR = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
        requestLSR.predicate = NSPredicate(
            format: "interval > 0 AND start > %@",
            Date().addingTimeInterval(-24.hours.timeInterval) as NSDate
        )
        let sortLSR = NSSortDescriptor(key: "start", ascending: false)
        requestLSR.sortDescriptors = [sortLSR]

        return await privateContext.perform {
            do {
                let lsr = try self.privateContext.fetch(requestLSR)

                // Compute LoopStats for 24 hours
                let oneDayLoops = self.loops(lsr)

                return LoopCycles(
                    loops: oneDayLoops.loops,
                    errors: oneDayLoops.errors,
                    readings: Int(oneDayGlucose),
                    success_rate: oneDayLoops.success_rate,
                    avg_interval: oneDayLoops.avg_interval,
                    median_interval: oneDayLoops.median_interval,
                    min_interval: oneDayLoops.min_interval,
                    max_interval: oneDayLoops.max_interval,
                    avg_duration: oneDayLoops.avg_duration,
                    median_duration: oneDayLoops.median_duration,
                    min_duration: oneDayLoops.max_duration,
                    max_duration: oneDayLoops.max_duration
                )
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to get Loop statistics for Statistics Upload"
                )
                return LoopCycles(
                    loops: 0,
                    errors: 0,
                    readings: 0,
                    success_rate: 0,
                    avg_interval: 0,
                    median_interval: 0,
                    min_interval: 0,
                    max_interval: 0,
                    avg_duration: 0,
                    median_duration: 0,
                    min_duration: 0,
                    max_duration: 0
                )
            }
        }
    }

    private func glucoseForStats() async -> (
        oneDayGlucose: (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double),
        eA1cDisplayUnit: EstimatedA1cDisplayUnit,
        numberofDays: Double,
        TimeInRange: TIRs,
        avg: Averages,
        hbs: Durations,
        variance: Variance
    )? {
        do {
            // Get the Glucose Values
            let glucose24h = try await fetchGlucose(predicate: NSPredicate.predicateForOneDayAgo, fetchLimit: 288, batchSize: 50)
            let glucoseOneWeek = try await fetchGlucose(
                predicate: NSPredicate.predicateForOneWeek,
                fetchLimit: 288 * 7,
                batchSize: 250
            )
            let glucoseOneMonth = try await fetchGlucose(
                predicate: NSPredicate.predicateForOneMonth,
                fetchLimit: 288 * 7 * 30,
                batchSize: 500
            )
            let glucoseThreeMonths = try await fetchGlucose(
                predicate: NSPredicate.predicateForThreeMonths,
                fetchLimit: 288 * 7 * 30 * 3,
                batchSize: 1000
            )

            return await privateContext.perform {
                let units = self.settingsManager.settings.units

                // First date
                let previous = glucoseThreeMonths.last?.date ?? Date()
                // Last date (recent)
                let current = glucoseThreeMonths.first?.date ?? Date()
                // Total time in days
                let numberOfDays = (current - previous).timeInterval / 8.64E4

                // Get glucose computations for every case
                let oneDayGlucose = self.glucoseStats(glucose24h)
                let sevenDaysGlucose = self.glucoseStats(glucoseOneWeek)
                let thirtyDaysGlucose = self.glucoseStats(glucoseOneMonth)
                let totalDaysGlucose = self.glucoseStats(glucoseThreeMonths)

                let median = Durations(
                    day: self.roundDecimal(Decimal(oneDayGlucose.median), 1),
                    week: self.roundDecimal(Decimal(sevenDaysGlucose.median), 1),
                    month: self.roundDecimal(Decimal(thirtyDaysGlucose.median), 1),
                    total: self.roundDecimal(Decimal(totalDaysGlucose.median), 1)
                )

                let eA1cDisplayUnit = self.settingsManager.settings.eA1cDisplayUnit

                let hbs = Durations(
                    day: eA1cDisplayUnit == .mmolMol ?
                        self.roundDecimal(Decimal(oneDayGlucose.ifcc), 1) :
                        self.roundDecimal(Decimal(oneDayGlucose.ngsp), 1),
                    week: eA1cDisplayUnit == .mmolMol ?
                        self.roundDecimal(Decimal(sevenDaysGlucose.ifcc), 1) :
                        self.roundDecimal(Decimal(sevenDaysGlucose.ngsp), 1),
                    month: eA1cDisplayUnit == .mmolMol ?
                        self.roundDecimal(Decimal(thirtyDaysGlucose.ifcc), 1) :
                        self.roundDecimal(Decimal(thirtyDaysGlucose.ngsp), 1),
                    total: eA1cDisplayUnit == .mmolMol ?
                        self.roundDecimal(Decimal(totalDaysGlucose.ifcc), 1) :
                        self.roundDecimal(Decimal(totalDaysGlucose.ngsp), 1)
                )

                var oneDay_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                var sevenDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                var thirtyDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                var totalDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                // Get TIR computations for every case
                oneDay_ = self.tir(glucose24h)
                sevenDays_ = self.tir(glucoseOneWeek)
                thirtyDays_ = self.tir(glucoseOneMonth)
                totalDays_ = self.tir(glucoseThreeMonths)

                let tir = Durations(
                    day: self.roundDecimal(Decimal(oneDay_.TIR), 1),
                    week: self.roundDecimal(Decimal(sevenDays_.TIR), 1),
                    month: self.roundDecimal(Decimal(thirtyDays_.TIR), 1),
                    total: self.roundDecimal(Decimal(totalDays_.TIR), 1)
                )
                let hypo = Durations(
                    day: Decimal(oneDay_.hypos),
                    week: Decimal(sevenDays_.hypos),
                    month: Decimal(thirtyDays_.hypos),
                    total: Decimal(totalDays_.hypos)
                )
                let hyper = Durations(
                    day: Decimal(oneDay_.hypers),
                    week: Decimal(sevenDays_.hypers),
                    month: Decimal(thirtyDays_.hypers),
                    total: Decimal(totalDays_.hypers)
                )
                let normal = Durations(
                    day: Decimal(oneDay_.normal_),
                    week: Decimal(sevenDays_.normal_),
                    month: Decimal(thirtyDays_.normal_),
                    total: Decimal(totalDays_.normal_)
                )
                let range = Threshold(
                    low: units == .mmolL ? self.roundDecimal(self.settingsManager.settings.low.asMmolL, 1) :
                        self.roundDecimal(self.settingsManager.settings.low, 0),
                    high: units == .mmolL ? self.roundDecimal(self.settingsManager.settings.high.asMmolL, 1) :
                        self.roundDecimal(self.settingsManager.settings.high, 0)
                )
                let TimeInRange = TIRs(
                    TIR: tir,
                    Hypos: hypo,
                    Hypers: hyper,
                    Threshold: range,
                    Euglycemic: normal
                )
                let avgs = Durations(
                    day: self.roundDecimal(Decimal(oneDayGlucose.average), 1),
                    week: self.roundDecimal(Decimal(sevenDaysGlucose.average), 1),
                    month: self.roundDecimal(Decimal(thirtyDaysGlucose.average), 1),
                    total: self.roundDecimal(Decimal(totalDaysGlucose.average), 1)
                )
                let avg = Averages(Average: avgs, Median: median)
                // Standard Deviations
                let standardDeviations = Durations(
                    day: self.roundDecimal(Decimal(oneDayGlucose.sd), 1),
                    week: self.roundDecimal(Decimal(sevenDaysGlucose.sd), 1),
                    month: self.roundDecimal(Decimal(thirtyDaysGlucose.sd), 1),
                    total: self.roundDecimal(Decimal(totalDaysGlucose.sd), 1)
                )
                // CV = standard deviation / sample mean x 100
                let cvs = Durations(
                    day: self.roundDecimal(Decimal(oneDayGlucose.cv), 1),
                    week: self.roundDecimal(Decimal(sevenDaysGlucose.cv), 1),
                    month: self.roundDecimal(Decimal(thirtyDaysGlucose.cv), 1),
                    total: self.roundDecimal(Decimal(totalDaysGlucose.cv), 1)
                )
                let variance = Variance(SD: standardDeviations, CV: cvs)

                return (oneDayGlucose, eA1cDisplayUnit, numberOfDays, TimeInRange, avg, hbs, variance)
            }
        } catch {
            debug(
                .apsManager,
                "\(DebuggingIdentifiers.failed) Error fetching glucose for stats: \(error)"
            )
            return nil
        }
    }

    private func loopStats(loopStatRecord: LoopStats) {
        privateContext.perform {
            let nLS = LoopStatRecord(context: self.privateContext)
            nLS.start = loopStatRecord.start
            nLS.end = loopStatRecord.end ?? Date()
            nLS.loopStatus = loopStatRecord.loopStatus
            nLS.duration = loopStatRecord.duration ?? 0.0
            nLS.interval = loopStatRecord.interval ?? 0.0

            do {
                guard self.privateContext.hasChanges else { return }
                try self.privateContext.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    private func processError(_ error: Error) {
        warning(.apsManager, "\(error)")
        lastError.send(error)
    }

    private func createBolusReporter() {
        bolusReporter = pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
        bolusReporter?.addObserver(self)
    }

    private func clearBolusReporter() {
        bolusReporter?.removeObserver(self)
        bolusReporter = nil
        processQueue.asyncAfter(deadline: .now() + 0.5) {
            self.bolusProgress.send(nil)
        }
    }
}

private extension PumpManager {
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { error in
                if let error = error {
                    debug(.apsManager, "Temp basal failed: \(unitsPerHour) for: \(duration)")
                    continuation.resume(throwing: error)
                } else {
                    debug(.apsManager, "Temp basal succeeded: \(unitsPerHour) for: \(duration)")
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func enactBolus(units: Double, automatic: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let automaticValue = automatic ? BolusActivationType.automatic : BolusActivationType.manualRecommendationAccepted

            self.enactBolus(units: units, activationType: automaticValue) { error in
                if let error = error {
                    debug(.apsManager, "Bolus failed: \(units)")
                    continuation.resume(throwing: error)
                } else {
                    debug(.apsManager, "Bolus succeeded: \(units)")
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func cancelBolus() async throws -> DoseEntry? {
        try await withCheckedThrowingContinuation { continuation in
            self.cancelBolus { result in
                switch result {
                case let .success(dose):
                    debug(.apsManager, "Cancel Bolus succeeded")
                    continuation.resume(returning: dose)
                case let .failure(error):
                    debug(.apsManager, "Cancel Bolus failed")
                    continuation.resume(throwing: APSError.pumpError(error))
                }
            }
        }
    }

    func suspendDelivery() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.suspendDelivery { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func resumeDelivery() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.resumeDelivery { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

extension BaseAPSManager: PumpManagerStatusObserver {
    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        let percent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)

        privateContext.perform {
            /// only update the last item with the current battery infos instead of saving a new one each time
            let fetchRequest: NSFetchRequest<OpenAPS_Battery> = OpenAPS_Battery.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            fetchRequest.predicate = NSPredicate.predicateFor30MinAgo
            fetchRequest.fetchLimit = 1

            do {
                let results = try self.privateContext.fetch(fetchRequest)
                let batteryToStore: OpenAPS_Battery

                if let existingBattery = results.first {
                    batteryToStore = existingBattery
                } else {
                    batteryToStore = OpenAPS_Battery(context: self.privateContext)
                    batteryToStore.id = UUID()
                }

                batteryToStore.date = Date()
                batteryToStore.percent = Double(percent)
                batteryToStore.voltage = nil
                batteryToStore.status = percent > 10 ? "normal" : "low"
                batteryToStore.display = status.pumpBatteryChargeRemaining != nil

                guard self.privateContext.hasChanges else { return }
                try self.privateContext.save()
            } catch {
                print("Failed to fetch or save battery: \(error.localizedDescription)")
            }
        }
        // TODO: - remove this after ensuring that NS still gets the same infos from Core Data
        storage.save(status.pumpStatus, as: OpenAPS.Monitor.status)
    }
}

extension BaseAPSManager: DoseProgressObserver {
    func doseProgressReporterDidUpdate(_ doseProgressReporter: DoseProgressReporter) {
        bolusProgress.send(Decimal(doseProgressReporter.progress.percentComplete))
        if doseProgressReporter.progress.isComplete {
            clearBolusReporter()
        }
    }
}

extension PumpManagerStatus {
    var pumpStatus: PumpStatus {
        let bolusing = bolusState != .noBolus
        let suspended = basalDeliveryState?.isSuspended ?? true
        let type = suspended ? StatusType.suspended : (bolusing ? .bolusing : .normal)
        return PumpStatus(status: type, bolusing: bolusing, suspended: suspended, timestamp: Date())
    }
}
