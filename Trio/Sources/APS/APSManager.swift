import Combine
import CoreData
import Foundation
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject

protocol APSManager {
    func heartbeat(date: Date)
    func autotune() async -> Autotune?
    func enactBolus(amount: Double, isSMB: Bool) async
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
    func makeProfiles() async throws -> Bool
    func determineBasal() async -> Bool
    func determineBasalSync() async
    func simulateDetermineBasal(carbs: Decimal, iob: Decimal) async -> Determination?
    func roundBolus(amount: Decimal) -> Decimal
    var lastError: CurrentValueSubject<Error?, Never> { get }
    func cancelBolus() async
}

enum APSError: LocalizedError {
    case pumpError(Error)
    case invalidPumpState(message: String)
    case glucoseError(message: String)
    case apsError(message: String)
    case deviceSyncError(message: String)
    case manualBasalTemp(message: String)

    var errorDescription: String? {
        switch self {
        case let .pumpError(error):
            return "Pump error: \(error.localizedDescription)"
        case let .invalidPumpState(message):
            return "Error: Invalid Pump State: \(message)"
        case let .glucoseError(message):
            return "Error: Invalid glucose: \(message)"
        case let .apsError(message):
            return "APS error: \(message)"
        case let .deviceSyncError(message):
            return "Sync error: \(message)"
        case let .manualBasalTemp(message):
            return "Manual Basal Temp : \(message)"
        }
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
    @Injected() private var broadcaster: Broadcaster!
    @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date()
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

    private var backGroundTaskID: UIBackgroundTaskIdentifier?

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
        openAPS = OpenAPS(storage: storage)
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
                    try await makeProfiles()
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
        Task {
            // check the last start of looping is more the loopInterval but the previous loop was completed
            if lastLoopDate > lastLoopStartDate {
                guard lastLoopStartDate.addingTimeInterval(Config.loopInterval) < Date() else {
                    debug(.apsManager, "too close to do a loop : \(lastLoopStartDate)")
                    return
                }
            }

            guard !isLooping.value else {
                warning(.apsManager, "Loop already in progress. Skip recommendation.")
                return
            }

            // start background time extension
            backGroundTaskID = await UIApplication.shared.beginBackgroundTask(withName: "Loop starting") {
                guard let backgroundTask = self.backGroundTaskID else { return }
                Task {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
                self.backGroundTaskID = .invalid
            }

            lastLoopStartDate = Date()

            var previousLoop = [LoopStatRecord]()
            var interval: Double?

            do {
                try await privateContext.perform {
                    let requestStats = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
                    let sortStats = NSSortDescriptor(key: "end", ascending: false)
                    requestStats.sortDescriptors = [sortStats]
                    requestStats.fetchLimit = 1
                    previousLoop = try self.privateContext.fetch(requestStats)

                    if (previousLoop.first?.end ?? .distantFuture) < self.lastLoopStartDate {
                        interval = self.roundDouble(
                            (self.lastLoopStartDate - (previousLoop.first?.end ?? Date())).timeInterval / 60,
                            1
                        )
                    }
                }
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch the last loop with error: \(error.userInfo)"
                )
            }

            var loopStatRecord = LoopStats(
                start: lastLoopStartDate,
                loopStatus: "Starting",
                interval: interval
            )

            isLooping.send(true)

            do {
                if await !determineBasal() {
                    throw APSError.apsError(message: "Determine basal failed")
                }

                // Open loop completed
                guard settings.closedLoop else {
                    loopStatRecord.end = Date()
                    loopStatRecord.duration = roundDouble((loopStatRecord.end! - loopStatRecord.start).timeInterval / 60, 2)
                    loopStatRecord.loopStatus = "Success"
                    await loopCompleted(loopStatRecord: loopStatRecord)
                    return
                }

                // Closed loop - enact Determination
                try await enactDetermination()
                loopStatRecord.end = Date()
                loopStatRecord.duration = roundDouble((loopStatRecord.end! - loopStatRecord.start).timeInterval / 60, 2)
                loopStatRecord.loopStatus = "Success"
                await loopCompleted(loopStatRecord: loopStatRecord)
            } catch {
                loopStatRecord.end = Date()
                loopStatRecord.duration = roundDouble((loopStatRecord.end! - loopStatRecord.start).timeInterval / 60, 2)
                loopStatRecord.loopStatus = error.localizedDescription
                await loopCompleted(error: error, loopStatRecord: loopStatRecord)
            }

            if let nightscoutManager = nightscout {
                await nightscoutManager.uploadCarbs()
                await nightscoutManager.uploadPumpHistory()
                await nightscoutManager.uploadOverrides()
                await nightscoutManager.uploadTempTargets()
            }

            // End background task after all the operations are completed
            if let backgroundTask = self.backGroundTaskID {
                await UIApplication.shared.endBackgroundTask(backgroundTask)
                self.backGroundTaskID = .invalid
            }
        }
    }

//     Loop exit point
    private func loopCompleted(error: Error? = nil, loopStatRecord: LoopStats) async {
        isLooping.send(false)

        if let error = error {
            warning(.apsManager, "Loop failed with error: \(error.localizedDescription)")
            if let backgroundTask = backGroundTaskID {
                await UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundTaskID = .invalid
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
        if let backgroundTask = backGroundTaskID {
            await UIApplication.shared.endBackgroundTask(backgroundTask)
            backGroundTaskID = .invalid
        }
    }

    private func verifyStatus() -> Error? {
        guard let pump = pumpManager else {
            return APSError.invalidPumpState(message: "Pump not set")
        }
        let status = pump.status.pumpStatus

        guard !status.bolusing else {
            return APSError.invalidPumpState(message: "Pump is bolusing")
        }

        guard !status.suspended else {
            return APSError.invalidPumpState(message: "Pump suspended")
        }

        let reservoir = storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self) ?? 100
        guard reservoir >= 0 else {
            return APSError.invalidPumpState(message: "Reservoir is empty")
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

    func determineBasal() async -> Bool {
        debug(.apsManager, "Start determine basal")

        // Fetch glucose asynchronously
        let glucose = await fetchGlucose(predicate: NSPredicate.predicateForOneHourAgo, fetchLimit: 6)

        // Perform the context-related checks and actions
        let isValidGlucoseData = await privateContext.perform {
            guard glucose.count > 2 else {
                debug(.apsManager, "Not enough glucose data")
                self.processError(APSError.glucoseError(message: "Not enough glucose data"))
                return false
            }

            let dateOfLastGlucose = glucose.first?.date
            guard dateOfLastGlucose ?? Date() >= Date().addingTimeInterval(-12.minutes.timeInterval) else {
                debug(.apsManager, "Glucose data is stale")
                self.processError(APSError.glucoseError(message: "Glucose data is stale"))
                return false
            }

            guard !GlucoseStored.glucoseIsFlat(glucose) else {
                debug(.apsManager, "Glucose data is too flat")
                self.processError(APSError.glucoseError(message: "Glucose data is too flat"))
                return false
            }

            return true
        }

        guard isValidGlucoseData else {
            debug(.apsManager, "Glucose validation failed")
            processError(APSError.glucoseError(message: "Glucose validation failed"))
            return false
        }

        do {
            let now = Date()

            // Start fetching asynchronously
            let (currentTemp, _, _, _) = try await (
                fetchCurrentTempBasal(date: now),
                makeProfiles(),
                autosense(),
                dailyAutotune()
            )

            // Determine basal using the fetched temp and current time
            let determination = try await openAPS.determineBasal(currentTemp: currentTemp, clock: now)

            if let determination = determination {
                DispatchQueue.main.async {
                    self.broadcaster.notify(DeterminationObserver.self, on: .main) {
                        $0.determinationDidUpdate(determination)
                    }
                }
                return true
            } else {
                return false
            }
        } catch {
            debug(.apsManager, "Error determining basal: \(error)")
            return false
        }
    }

    func determineBasalSync() async {
        _ = await determineBasal()
    }

    func simulateDetermineBasal(carbs: Decimal, iob: Decimal) async -> Determination? {
        do {
            let temp = await fetchCurrentTempBasal(date: Date.now)
            return try await openAPS.determineBasal(currentTemp: temp, clock: Date(), carbs: carbs, iob: iob, simulation: true)
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Error occurred in invokeDummyDetermineBasalSync: \(error)"
            )
            return nil
        }
    }

    func makeProfiles() async throws -> Bool {
        let tunedProfile = await openAPS.makeProfiles(useAutotune: settings.useAutotune)
        if let basalProfile = tunedProfile?.basalProfile {
            processQueue.async {
                self.broadcaster.notify(BasalProfileObserver.self, on: self.processQueue) {
                    $0.basalProfileDidChange(basalProfile)
                }
            }
        }
        return tunedProfile != nil
    }

    func roundBolus(amount: Decimal) -> Decimal {
        guard let pump = pumpManager else { return amount }
        let rounded = Decimal(pump.roundToSupportedBolusVolume(units: Double(amount)))
        let maxBolus = Decimal(pump.roundToSupportedBolusVolume(units: Double(settingsManager.pumpSettings.maxBolus)))
        return min(rounded, maxBolus)
    }

    private var bolusReporter: DoseProgressReporter?

    func enactBolus(amount: Double, isSMB: Bool) async {
        if amount <= 0 {
            return
        }

        if let error = verifyStatus() {
            processError(error)
            processQueue.async {
                self.broadcaster.notify(BolusFailureObserver.self, on: self.processQueue) {
                    $0.bolusDidFail()
                }
            }
            return
        }

        guard let pump = pumpManager else { return }

        let roundedAmount = pump.roundToSupportedBolusVolume(units: amount)

        debug(.apsManager, "Enact bolus \(roundedAmount), manual \(!isSMB)")

        do {
            try await pump.enactBolus(units: roundedAmount, automatic: isSMB)
            debug(.apsManager, "Bolus succeeded")
            if !isSMB {
                await determineBasalSync()
            }
            bolusProgress.send(0)
        } catch {
            warning(.apsManager, "Bolus failed with error: \(error.localizedDescription)")
            processError(APSError.pumpError(error))
            if !isSMB {
                processQueue.async {
                    self.broadcaster.notify(BolusFailureObserver.self, on: self.processQueue) {
                        $0.bolusDidFail()
                    }
                }
            }
        }
    }

    func cancelBolus() async {
        guard let pump = pumpManager, pump.status.pumpStatus.bolusing else { return }
        debug(.apsManager, "Cancel bolus")
        do {
            _ = try await pump.cancelBolus()
            debug(.apsManager, "Bolus cancelled")
        } catch {
            debug(.apsManager, "Bolus cancellation failed with error: \(error.localizedDescription)")
            processError(APSError.pumpError(error))
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
            debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
            processError(APSError.pumpError(error))
        }
    }

    func dailyAutotune() async throws -> Bool {
        guard settings.useAutotune else {
            return false
        }

        let now = Date()

        guard lastAutotuneDate.isBeforeDate(now, granularity: .day) else {
            return false
        }
        lastAutotuneDate = now

        let result = await autotune()
        return result != nil
    }

    func autotune() async -> Autotune? {
        await openAPS.autotune()
    }

    private func fetchCurrentTempBasal(date: Date) async -> TempBasal {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
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
        guard let determinationID = await determinationStorage
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
        guard let determinationID = await determinationStorage
            .fetchLastDeterminationObjectID(predicate: NSPredicate.predicateFor30MinAgoForDetermination).first
        else {
            return
        }
        await privateContext.perform {
            if let determinationUpdated = self.privateContext.object(with: determinationID) as? OrefDetermination {
                determinationUpdated.timestamp = Date()
                determinationUpdated.enacted = wasEnacted
                determinationUpdated.isUploadedToNS = false

                do {
                    guard self.privateContext.hasChanges else { return }
                    try self.privateContext.save()
                    debugPrint("Update successful in reportEnacted() \(DebuggingIdentifiers.succeeded)")
                } catch {
                    debugPrint(
                        "Failed  \(DebuggingIdentifiers.succeeded) to save context in reportEnacted(): \(error.localizedDescription)"
                    )
                }

                debug(.apsManager, "Determination enacted. Enacted: \(wasEnacted)")

                Task.detached(priority: .low) {
                    await self.statistics()
                }
            } else {
                debugPrint("Failed to update OrefDetermination in reportEnacted()")
            }
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
    func fetchGlucose(predicate: NSPredicate, fetchLimit: Int? = nil, batchSize: Int? = nil) async -> [GlucoseStored] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: privateContext,
            predicate: predicate,
            key: "date",
            ascending: false,
            fetchLimit: fetchLimit,
            batchSize: batchSize
        )

        return await privateContext.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                return []
            }

            return glucoseResults
        }
    }

    // TODO: - Refactor this whole shit here...

    // Add to statistics.JSON for upload to NS.
    private func statistics() async {
        let now = Date()
        if settingsManager.settings.uploadStats != nil {
            let hour = Calendar.current.component(.hour, from: now)
            guard hour > 20 else {
                return
            }

            // MARK: - Core Data related

            async let glucoseStats = glucoseForStats()
            async let lastLoopForStats = lastLoopForStats()
            async let carbTotal = carbsForStats()
            async let preferences = settingsManager.preferences

            let loopStats = await loopStats(oneDayGlucose: await glucoseStats.oneDayGlucose.readings)

            // Only save and upload once per day
            guard (-1 * (await lastLoopForStats ?? .distantPast).timeIntervalSinceNow.hours) > 22 else { return }

            let units = settingsManager.settings.units

            // MARK: - Not Core Data related stuff

            let pref = await preferences
            var algo_ = "Oref0"

            if pref.sigmoid, pref.enableDynamicCR {
                algo_ = "Dynamic ISF + CR: Sigmoid"
            } else if pref.sigmoid, !pref.enableDynamicCR {
                algo_ = "Dynamic ISF: Sigmoid"
            } else if pref.useNewFormula, pref.enableDynamicCR {
                algo_ = "Dynamic ISF + CR: Logarithmic"
            } else if pref.useNewFormula, !pref.sigmoid,!pref.enableDynamicCR {
                algo_ = "Dynamic ISF: Logarithmic"
            }
            let af = pref.adjustmentFactor
            let insulin_type = pref.curve
//            let buildDate = Bundle.main.buildDate // TODO: fix this
            let version = Bundle.main.releaseVersionNumber
            let build = Bundle.main.buildVersionNumber

            // Read branch information from branch.txt instead of infoDictionary
            var branch = "Unknown"
            if let branchFileURL = Bundle.main.url(forResource: "branch", withExtension: "txt"),
               let branchFileContent = try? String(contentsOf: branchFileURL)
            {
                let lines = branchFileContent.components(separatedBy: .newlines)
                for line in lines {
                    let components = line.components(separatedBy: "=")
                    if components.count == 2 {
                        let key = components[0].trimmingCharacters(in: .whitespaces)
                        let value = components[1].trimmingCharacters(in: .whitespaces)

                        if key == "BRANCH" {
                            branch = value
                            break
                        }
                    }
                }
            } else {
                branch = "Unknown"
            }

            let copyrightNotice_ = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
            let pump_ = pumpManager?.localizedTitle ?? ""
            let cgm = settingsManager.settings.cgm
            let file = OpenAPS.Monitor.statistics
            var iPa: Decimal = 75
            if pref.useCustomPeakTime {
                iPa = pref.insulinPeakTime
            } else if pref.curve.rawValue == "rapid-acting" {
                iPa = 65
            } else if pref.curve.rawValue == "ultra-rapid" {
                iPa = 50
            }

            // Insulin placeholder
            let insulin = Ins(
                TDD: 0,
                bolus: 0,
                temp_basal: 0,
                scheduled_basal: 0,
                total_average: 0
            )
            let processedGlucoseStats = await glucoseStats
            let hbA1cDisplayUnit = processedGlucoseStats.hbA1cDisplayUnit

            let dailystat = await Statistics(
                created_at: Date(),
                iPhone: UIDevice.current.getDeviceId,
                iOS: UIDevice.current.getOSInfo,
                Build_Version: version ?? "",
                Build_Number: build ?? "1",
                Branch: branch,
                CopyRightNotice: String(copyrightNotice_.prefix(32)),
                Build_Date: Date(), // TODO: fix this
                Algorithm: algo_,
                AdjustmentFactor: af,
                Pump: pump_,
                CGM: cgm.rawValue,
                insulinType: insulin_type.rawValue,
                peakActivityTime: iPa,
                Carbs_24h: await carbTotal,
                GlucoseStorage_Days: Decimal(roundDouble(processedGlucoseStats.numberofDays, 1)),
                Statistics: Stats(
                    Distribution: processedGlucoseStats.TimeInRange,
                    Glucose: processedGlucoseStats.avg,
                    HbA1c: processedGlucoseStats.hbs,
                    Units: Units(Glucose: units.rawValue, HbA1c: hbA1cDisplayUnit.rawValue),
                    LoopCycles: loopStats,
                    Insulin: insulin,
                    Variance: processedGlucoseStats.variance
                )
            )
            storage.save(dailystat, as: file)

            await saveStatsToCoreData()
        }
    }

    private func saveStatsToCoreData() async {
        await privateContext.perform {
            let saveStatsCoreData = StatsData(context: self.privateContext)
            saveStatsCoreData.lastrun = Date()

            do {
                guard self.privateContext.hasChanges else { return }
                try self.privateContext.save()
            } catch {
                print(error.localizedDescription)
            }
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

    private func carbsForStats() async -> Decimal {
        let requestCarbs = CarbEntryStored.fetchRequest() as NSFetchRequest<CarbEntryStored>
        let daysAgo = Date().addingTimeInterval(-1.days.timeInterval)
        requestCarbs.predicate = NSPredicate(format: "carbs > 0 AND date > %@", daysAgo as NSDate)
        requestCarbs.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

        return await privateContext.perform {
            do {
                let carbs = try self.privateContext.fetch(requestCarbs)
                debugPrint(
                    "APSManager: statistics() -> \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) fetched carbs"
                )

                return carbs.reduce(0) { sum, meal in
                    let mealCarbs = Decimal(string: "\(meal.carbs)") ?? Decimal.zero
                    return sum + mealCarbs
                }
            } catch {
                debugPrint(
                    "APSManager: statistics() -> \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) error while fetching carbs"
                )
                return 0
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

    private func tddForStats() async -> (currentTDD: Decimal, tddTotalAverage: Decimal) {
        let requestTDD = OrefDetermination.fetchRequest() as NSFetchRequest<NSFetchRequestResult>
        let sort = NSSortDescriptor(key: "timestamp", ascending: false)
        let daysOf14Ago = Date().addingTimeInterval(-14.days.timeInterval)
        requestTDD.predicate = NSPredicate(format: "timestamp > %@", daysOf14Ago as NSDate)
        requestTDD.sortDescriptors = [sort]
        requestTDD.propertiesToFetch = ["timestamp", "totalDailyDose"]
        requestTDD.resultType = .dictionaryResultType

        var currentTDD: Decimal = 0
        var tddTotalAverage: Decimal = 0

        let results = await privateContext.perform {
            do {
                let fetchedResults = try self.privateContext.fetch(requestTDD) as? [[String: Any]]
                return fetchedResults ?? []
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to get TDD Data for Statistics Upload")
                return []
            }
        }

        if !results.isEmpty {
            if let latestTDD = results.first?["totalDailyDose"] as? NSDecimalNumber {
                currentTDD = latestTDD.decimalValue
            }
            let tddArray = results.compactMap { ($0["totalDailyDose"] as? NSDecimalNumber)?.decimalValue }
            if !tddArray.isEmpty {
                tddTotalAverage = tddArray.reduce(0, +) / Decimal(tddArray.count)
            }
        }

        return (currentTDD, tddTotalAverage)
    }

    private func glucoseForStats() async
        -> (
            oneDayGlucose: (
                ifcc: Double,
                ngsp: Double,
                average: Double,
                median: Double,
                sd: Double,
                cv: Double,
                readings: Double
            ),
            hbA1cDisplayUnit: HbA1cDisplayUnit,
            numberofDays: Double,
            TimeInRange: TIRs,
            avg: Averages,
            hbs: Durations,
            variance: Variance
        )
    {
        // Get the Glucose Values
        let glucose24h = await fetchGlucose(predicate: NSPredicate.predicateForOneDayAgo, fetchLimit: 288, batchSize: 50)
        let glucoseOneWeek = await fetchGlucose(
            predicate: NSPredicate.predicateForOneWeek,
            fetchLimit: 288 * 7,
            batchSize: 250
        )
        let glucoseOneMonth = await fetchGlucose(
            predicate: NSPredicate.predicateForOneMonth,
            fetchLimit: 288 * 7 * 30,
            batchSize: 500
        )
        let glucoseThreeMonths = await fetchGlucose(
            predicate: NSPredicate.predicateForThreeMonths,
            fetchLimit: 288 * 7 * 30 * 3,
            batchSize: 1000
        )

        var result: (
            oneDayGlucose: (
                ifcc: Double,
                ngsp: Double,
                average: Double,
                median: Double,
                sd: Double,
                cv: Double,
                readings: Double
            ),
            hbA1cDisplayUnit: HbA1cDisplayUnit,
            numberofDays: Double,
            TimeInRange: TIRs,
            avg: Averages,
            hbs: Durations,
            variance: Variance
        )?

        await privateContext.perform {
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

            let hbA1cDisplayUnit = self.settingsManager.settings.hbA1cDisplayUnit

            let hbs = Durations(
                day: ((units == .mmolL && hbA1cDisplayUnit == .mmolMol) || (units == .mgdL && hbA1cDisplayUnit == .percent)) ?
                    self.roundDecimal(Decimal(oneDayGlucose.ifcc), 1) : self.roundDecimal(Decimal(oneDayGlucose.ngsp), 1),
                week: ((units == .mmolL && hbA1cDisplayUnit == .mmolMol) || (units == .mgdL && hbA1cDisplayUnit == .percent)) ?
                    self.roundDecimal(Decimal(sevenDaysGlucose.ifcc), 1) : self
                    .roundDecimal(Decimal(sevenDaysGlucose.ngsp), 1),
                month: ((units == .mmolL && hbA1cDisplayUnit == .mmolMol) || (units == .mgdL && hbA1cDisplayUnit == .percent)) ?
                    self.roundDecimal(Decimal(thirtyDaysGlucose.ifcc), 1) : self
                    .roundDecimal(Decimal(thirtyDaysGlucose.ngsp), 1),
                total: ((units == .mmolL && hbA1cDisplayUnit == .mmolMol) || (units == .mgdL && hbA1cDisplayUnit == .percent)) ?
                    self.roundDecimal(Decimal(totalDaysGlucose.ifcc), 1) : self.roundDecimal(Decimal(totalDaysGlucose.ngsp), 1)
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

            result = (oneDayGlucose, hbA1cDisplayUnit, numberOfDays, TimeInRange, avg, hbs, variance)
        }

        return result!
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
        warning(.apsManager, "\(error.localizedDescription)")
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
                batteryToStore.percent = Int16(percent)
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
