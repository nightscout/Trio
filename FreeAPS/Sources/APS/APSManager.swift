import Combine
import CoreData
import Foundation
import LoopKit
import LoopKitUI
import OmniBLE
import OmniKit
import RileyLinkKit
import SwiftDate
import Swinject

protocol APSManager {
    func heartbeat(date: Date)
    func autotune() -> AnyPublisher<Autotune?, Never>
    func enactBolus(amount: Double, isSMB: Bool)
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
    func enactTempBasal(rate: Double, duration: TimeInterval)
    func makeProfiles() -> AnyPublisher<Bool, Never>
    func determineBasal() -> AnyPublisher<Bool, Never>
    func determineBasalSync()
    func roundBolus(amount: Decimal) -> Decimal
    var lastError: CurrentValueSubject<Error?, Never> { get }
    func cancelBolus()
    func enactAnnouncement(_ announcement: Announcement)
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
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var nightscout: NightscoutManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var healthKitManager: HealthKitManager!
    @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date()
    @Persisted(key: "lastStartLoopDate") private var lastStartLoopDate: Date = .distantPast
    @Persisted(key: "lastLoopDate") var lastLoopDate: Date = .distantPast {
        didSet {
            lastLoopDateSubject.send(lastLoopDate)
        }
    }

    let coredataContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()

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

    var settings: FreeAPSSettings {
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
        // check the last start of looping is more the loopInterval but the previous loop was completed
        if lastLoopDate > lastStartLoopDate {
            guard lastStartLoopDate.addingTimeInterval(Config.loopInterval) < Date() else {
                debug(.apsManager, "too close to do a loop : \(lastStartLoopDate)")
                return
            }
        }

        guard !isLooping.value else {
            warning(.apsManager, "Loop already in progress. Skip recommendation.")
            return
        }

        // start background time extension
        backGroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Loop starting") {
            guard let backgroundTask = self.backGroundTaskID else { return }
            UIApplication.shared.endBackgroundTask(backgroundTask)
            self.backGroundTaskID = .invalid
        }

        debug(.apsManager, "Starting loop with a delay of \(UIApplication.shared.backgroundTimeRemaining.rounded())")

        lastStartLoopDate = Date()

        var previousLoop = [LoopStatRecord]()
        var interval: Double?

        coredataContext.performAndWait {
            let requestStats = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
            let sortStats = NSSortDescriptor(key: "end", ascending: false)
            requestStats.sortDescriptors = [sortStats]
            requestStats.fetchLimit = 1
            try? previousLoop = coredataContext.fetch(requestStats)

            if (previousLoop.first?.end ?? .distantFuture) < lastStartLoopDate {
                interval = roundDouble((lastStartLoopDate - (previousLoop.first?.end ?? Date())).timeInterval / 60, 1)
            }
        }

        var loopStatRecord = LoopStats(
            start: lastStartLoopDate,
            loopStatus: "Starting",
            interval: interval
        )

        isLooping.send(true)
        determineBasal()
            .replaceEmpty(with: false)
            .flatMap { [weak self] success -> AnyPublisher<Void, Error> in
                guard let self = self, success else {
                    return Fail(error: APSError.apsError(message: "Determine basal failed")).eraseToAnyPublisher()
                }

                // Open loop completed
                guard self.settings.closedLoop else {
                    self.nightscout.uploadStatus()
                    return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
                }

                self.nightscout.uploadStatus()

                // Closed loop - enact suggested
                return self.enactSuggested()
            }
            .sink { [weak self] completion in
                guard let self = self else { return }
                loopStatRecord.end = Date()
                loopStatRecord.duration = self.roundDouble(
                    (loopStatRecord.end! - loopStatRecord.start).timeInterval / 60,
                    2
                )
                if case let .failure(error) = completion {
                    loopStatRecord.loopStatus = error.localizedDescription
                    self.loopCompleted(error: error, loopStatRecord: loopStatRecord)
                } else {
                    loopStatRecord.loopStatus = "Success"
                    self.loopCompleted(loopStatRecord: loopStatRecord)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    // Loop exit point
    private func loopCompleted(error: Error? = nil, loopStatRecord: LoopStats) {
        isLooping.send(false)

        // save AH events
        let events = pumpHistoryStorage.recent()
        healthKitManager.saveIfNeeded(pumpEvents: events)

        if let error = error {
            warning(.apsManager, "Loop failed with error: \(error.localizedDescription)")
            if let backgroundTask = backGroundTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
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
            reportEnacted(received: error == nil)
        }

        // end of the BG tasks
        if let backgroundTask = backGroundTaskID {
            UIApplication.shared.endBackgroundTask(backgroundTask)
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

    private func autosens() -> AnyPublisher<Bool, Never> {
        guard let autosens = storage.retrieve(OpenAPS.Settings.autosense, as: Autosens.self),
              (autosens.timestamp ?? .distantPast).addingTimeInterval(30.minutes.timeInterval) > Date()
        else {
            return openAPS.autosense()
                .map { $0 != nil }
                .eraseToAnyPublisher()
        }

        return Just(false).eraseToAnyPublisher()
    }

    func determineBasal() -> AnyPublisher<Bool, Never> {
        debug(.apsManager, "Start determine basal")
        guard let glucose = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self), glucose.isNotEmpty else {
            debug(.apsManager, "Not enough glucose data")
            processError(APSError.glucoseError(message: "Not enough glucose data"))
            return Just(false).eraseToAnyPublisher()
        }

        let lastGlucoseDate = glucoseStorage.lastGlucoseDate()
        guard lastGlucoseDate >= Date().addingTimeInterval(-12.minutes.timeInterval) else {
            debug(.apsManager, "Glucose data is stale")
            processError(APSError.glucoseError(message: "Glucose data is stale"))
            return Just(false).eraseToAnyPublisher()
        }

        // Only let glucose be flat when 400 mg/dl
        if (glucoseStorage.recent().last?.glucose ?? 100) != 400 {
            guard glucoseStorage.isGlucoseNotFlat() else {
                debug(.apsManager, "Glucose data is too flat")
                processError(APSError.glucoseError(message: "Glucose data is too flat"))
                return Just(false).eraseToAnyPublisher()
            }
        }

        let now = Date()
        let temp = currentTemp(date: now)

        let mainPublisher = makeProfiles()
            .flatMap { _ in self.autosens() }
            .flatMap { _ in self.dailyAutotune() }
            .flatMap { _ in self.openAPS.determineBasal(currentTemp: temp, clock: now) }
            .map { suggestion -> Bool in
                if let suggestion = suggestion {
                    DispatchQueue.main.async {
                        self.broadcaster.notify(SuggestionObserver.self, on: .main) {
                            $0.suggestionDidUpdate(suggestion)
                        }
                    }
                }

                return suggestion != nil
            }
            .eraseToAnyPublisher()

        if temp.duration == 0,
           settings.closedLoop,
           settingsManager.preferences.unsuspendIfNoTemp,
           let pump = pumpManager,
           pump.status.pumpStatus.suspended
        {
            return pump.resumeDelivery()
                .flatMap { _ in mainPublisher }
                .replaceError(with: false)
                .eraseToAnyPublisher()
        }

        return mainPublisher
    }

    func determineBasalSync() {
        determineBasal().cancellable().store(in: &lifetime)
    }

    func makeProfiles() -> AnyPublisher<Bool, Never> {
        openAPS.makeProfiles(useAutotune: settings.useAutotune)
            .map { tunedProfile in
                if let basalProfile = tunedProfile?.basalProfile {
                    self.processQueue.async {
                        self.broadcaster.notify(BasalProfileObserver.self, on: self.processQueue) {
                            $0.basalProfileDidChange(basalProfile)
                        }
                    }
                }

                return tunedProfile != nil
            }
            .eraseToAnyPublisher()
    }

    func roundBolus(amount: Decimal) -> Decimal {
        guard let pump = pumpManager else { return amount }
        let rounded = Decimal(pump.roundToSupportedBolusVolume(units: Double(amount)))
        let maxBolus = Decimal(pump.roundToSupportedBolusVolume(units: Double(settingsManager.pumpSettings.maxBolus)))
        return min(rounded, maxBolus)
    }

    private var bolusReporter: DoseProgressReporter?

    func enactBolus(amount: Double, isSMB: Bool) {
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

        let roundedAmout = pump.roundToSupportedBolusVolume(units: amount)

        debug(.apsManager, "Enact bolus \(roundedAmout), manual \(!isSMB)")

        pump.enactBolus(units: roundedAmout, automatic: isSMB).sink { completion in
            if case let .failure(error) = completion {
                warning(.apsManager, "Bolus failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
                if !isSMB {
                    self.processQueue.async {
                        self.broadcaster.notify(BolusFailureObserver.self, on: self.processQueue) {
                            $0.bolusDidFail()
                        }
                    }
                }
            } else {
                debug(.apsManager, "Bolus succeeded")
                if !isSMB {
                    self.determineBasal().sink { _ in }.store(in: &self.lifetime)
                }
                self.bolusProgress.send(0)
            }
        } receiveValue: { _ in }
            .store(in: &lifetime)
    }

    func cancelBolus() {
        guard let pump = pumpManager, pump.status.pumpStatus.bolusing else { return }
        debug(.apsManager, "Cancel bolus")
        pump.cancelBolus().sink { completion in
            if case let .failure(error) = completion {
                debug(.apsManager, "Bolus cancellation failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
            } else {
                debug(.apsManager, "Bolus cancelled")
            }

            self.bolusReporter?.removeObserver(self)
            self.bolusReporter = nil
            self.bolusProgress.send(nil)
        } receiveValue: { _ in }
            .store(in: &lifetime)
    }

    func enactTempBasal(rate: Double, duration: TimeInterval) {
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
        pump.enactTempBasal(unitsPerHour: roundedAmout, for: duration) { error in
            if let error = error {
                debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
            } else {
                debug(.apsManager, "Temp Basal succeeded")
                let temp = TempBasal(duration: Int(duration / 60), rate: Decimal(rate), temp: .absolute, timestamp: Date())
                self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
                if rate == 0, duration == 0 {
                    self.pumpHistoryStorage.saveCancelTempEvents()
                }
            }
        }
    }

    func dailyAutotune() -> AnyPublisher<Bool, Never> {
        guard settings.useAutotune else {
            return Just(false).eraseToAnyPublisher()
        }

        let now = Date()

        guard lastAutotuneDate.isBeforeDate(now, granularity: .day) else {
            return Just(false).eraseToAnyPublisher()
        }
        lastAutotuneDate = now

        return autotune().map { $0 != nil }.eraseToAnyPublisher()
    }

    func autotune() -> AnyPublisher<Autotune?, Never> {
        openAPS.autotune().eraseToAnyPublisher()
    }

    func enactAnnouncement(_ announcement: Announcement) {
        guard let action = announcement.action else {
            warning(.apsManager, "Invalid Announcement action")
            return
        }

        guard let pump = pumpManager else {
            warning(.apsManager, "Pump is not set")
            return
        }

        debug(.apsManager, "Start enact announcement: \(action)")

        switch action {
        case let .bolus(amount):
            if let error = verifyStatus() {
                processError(error)
                return
            }
            let roundedAmount = pump.roundToSupportedBolusVolume(units: Double(amount))
            pump.enactBolus(units: roundedAmount, activationType: .manualRecommendationAccepted) { error in
                if let error = error {
                    // warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                    switch error {
                    case .uncertainDelivery:
                        // Do not generate notification on uncertain delivery error
                        break
                    default:
                        // Do not generate notifications for automatic boluses that fail.
                        warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                    }

                } else {
                    debug(.apsManager, "Announcement Bolus succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    self.bolusProgress.send(0)
                }
            }
        case let .pump(pumpAction):
            switch pumpAction {
            case .suspend:
                if let error = verifyStatus() {
                    processError(error)
                    return
                }
                pump.suspendDelivery { error in
                    if let error = error {
                        debug(.apsManager, "Pump not suspended by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump suspended by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                        self.nightscout.uploadStatus()
                    }
                }
            case .resume:
                guard pump.status.pumpStatus.suspended else {
                    return
                }
                pump.resumeDelivery { error in
                    if let error = error {
                        warning(.apsManager, "Pump not resumed by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump resumed by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                        self.nightscout.uploadStatus()
                    }
                }
            }
        case let .looping(closedLoop):
            settings.closedLoop = closedLoop
            debug(.apsManager, "Closed loop \(closedLoop) by Announcement")
            announcementsStorage.storeAnnouncements([announcement], enacted: true)
        case let .tempbasal(rate, duration):
            if let error = verifyStatus() {
                processError(error)
                return
            }
            // unable to do temp basal during manual temp basal 😁
            if isManualTempBasal {
                processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
                return
            }
            guard !settings.closedLoop else {
                return
            }
            let roundedRate = pump.roundToSupportedBasalRate(unitsPerHour: Double(rate))
            pump.enactTempBasal(unitsPerHour: roundedRate, for: TimeInterval(duration) * 60) { error in
                if let error = error {
                    warning(.apsManager, "Announcement TempBasal failed with error: \(error.localizedDescription)")
                } else {
                    debug(.apsManager, "Announcement TempBasal succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                }
            }
        }
    }

    private func currentTemp(date: Date) -> TempBasal {
        let defaultTemp = { () -> TempBasal in
            guard let temp = storage.retrieve(OpenAPS.Monitor.tempBasal, as: TempBasal.self) else {
                return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
            }
            let delta = Int((date.timeIntervalSince1970 - temp.timestamp.timeIntervalSince1970) / 60)
            let duration = max(0, temp.duration - delta)
            return TempBasal(duration: duration, rate: temp.rate, temp: .absolute, timestamp: date)
        }()

        guard let state = pumpManager?.status.basalDeliveryState else { return defaultTemp }
        switch state {
        case .active:
            return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: date)
        case let .tempBasal(dose):
            let rate = Decimal(dose.unitsPerHour)
            let durationMin = max(0, Int((dose.endDate.timeIntervalSince1970 - date.timeIntervalSince1970) / 60))
            return TempBasal(duration: durationMin, rate: rate, temp: .absolute, timestamp: date)
        default:
            return defaultTemp
        }
    }

    private func enactSuggested() -> AnyPublisher<Void, Error> {
        guard let suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self) else {
            return Fail(error: APSError.apsError(message: "Suggestion not found")).eraseToAnyPublisher()
        }

        guard Date().timeIntervalSince(suggested.deliverAt ?? .distantPast) < Config.eхpirationInterval else {
            return Fail(error: APSError.apsError(message: "Suggestion expired")).eraseToAnyPublisher()
        }

        guard let pump = pumpManager else {
            return Fail(error: APSError.apsError(message: "Pump not set")).eraseToAnyPublisher()
        }

        // unable to do temp basal during manual temp basal 😁
        if isManualTempBasal {
            return Fail(error: APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
                .eraseToAnyPublisher()
        }

        let basalPublisher: AnyPublisher<Void, Error> = Deferred { () -> AnyPublisher<Void, Error> in
            if let error = self.verifyStatus() {
                return Fail(error: error).eraseToAnyPublisher()
            }

            guard let rate = suggested.rate, let duration = suggested.duration else {
                // It is OK, no temp required
                debug(.apsManager, "No temp required")
                return Just(()).setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            return pump.enactTempBasal(unitsPerHour: Double(rate), for: TimeInterval(duration * 60)).map { _ in
                let temp = TempBasal(duration: duration, rate: rate, temp: .absolute, timestamp: Date())
                self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
                return ()
            }
            .eraseToAnyPublisher()
        }.eraseToAnyPublisher()

        let bolusPublisher: AnyPublisher<Void, Error> = Deferred { () -> AnyPublisher<Void, Error> in
            if let error = self.verifyStatus() {
                return Fail(error: error).eraseToAnyPublisher()
            }
            guard let units = suggested.units else {
                // It is OK, no bolus required
                debug(.apsManager, "No bolus required")
                return Just(()).setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            return pump.enactBolus(units: Double(units), automatic: true).map { _ in
                self.bolusProgress.send(0)
                return ()
            }
            .eraseToAnyPublisher()
        }.eraseToAnyPublisher()

        return basalPublisher.flatMap { bolusPublisher }.eraseToAnyPublisher()
    }

    private func reportEnacted(received: Bool) {
        if let suggestion = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self), suggestion.deliverAt != nil {
            var enacted = suggestion
            enacted.timestamp = Date()
            enacted.recieved = received

            storage.save(enacted, as: OpenAPS.Enact.enacted)

            debug(.apsManager, "Suggestion enacted. Received: \(received)")
            DispatchQueue.main.async {
                self.broadcaster.notify(EnactedSuggestionObserver.self, on: .main) {
                    $0.enactedSuggestionDidUpdate(enacted)
                }
            }
            nightscout.uploadStatus()
            statistics()
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

    private func tir(_ array: [Readings]) -> (TIR: Double, hypos: Double, hypers: Double, normal_: Double) {
        let glucose = array
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

    private func glucoseStats(_ fetchedGlucose: [Readings])
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

    // Add to statistics.JSON for upload to NS.
    private func statistics() {
        let now = Date()
        if settingsManager.settings.uploadStats {
            let hour = Calendar.current.component(.hour, from: now)
            guard hour > 20 else {
                return
            }
            coredataContext.performAndWait { [self] in
                var stats = [StatsData]()
                let requestStats = StatsData.fetchRequest() as NSFetchRequest<StatsData>
                let sortStats = NSSortDescriptor(key: "lastrun", ascending: false)
                requestStats.sortDescriptors = [sortStats]
                requestStats.fetchLimit = 1
                try? stats = coredataContext.fetch(requestStats)
                // Only save and upload once per day
                guard (-1 * (stats.first?.lastrun ?? .distantPast).timeIntervalSinceNow.hours) > 22 else { return }

                let units = self.settingsManager.settings.units
                let preferences = settingsManager.preferences

                // Carbs
                var carbs = [Carbohydrates]()
                var carbTotal: Decimal = 0
                let requestCarbs = Carbohydrates.fetchRequest() as NSFetchRequest<Carbohydrates>
                let daysAgo = Date().addingTimeInterval(-1.days.timeInterval)
                requestCarbs.predicate = NSPredicate(format: "carbs > 0 AND date > %@", daysAgo as NSDate)
                let sortCarbs = NSSortDescriptor(key: "date", ascending: true)
                requestCarbs.sortDescriptors = [sortCarbs]
                try? carbs = coredataContext.fetch(requestCarbs)
                carbTotal = carbs.map({ carbs in carbs.carbs as? Decimal ?? 0 }).reduce(0, +)

                // TDD
                var tdds = [TDD]()
                var currentTDD: Decimal = 0
                var tddTotalAverage: Decimal = 0
                let requestTDD = TDD.fetchRequest() as NSFetchRequest<TDD>
                let sort = NSSortDescriptor(key: "timestamp", ascending: false)
                let daysOf14Ago = Date().addingTimeInterval(-14.days.timeInterval)
                requestTDD.predicate = NSPredicate(format: "timestamp > %@", daysOf14Ago as NSDate)
                requestTDD.sortDescriptors = [sort]
                try? tdds = coredataContext.fetch(requestTDD)

                if !tdds.isEmpty {
                    currentTDD = tdds[0].tdd?.decimalValue ?? 0
                    let tddArray = tdds.compactMap({ insulin in insulin.tdd as? Decimal ?? 0 })
                    tddTotalAverage = tddArray.reduce(0, +) / Decimal(tddArray.count)
                }

                var algo_ = "Oref0"

                if preferences.sigmoid, preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF + CR: Sigmoid"
                } else if preferences.sigmoid, !preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF: Sigmoid"
                } else if preferences.useNewFormula, preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF + CR: Logarithmic"
                } else if preferences.useNewFormula, !preferences.sigmoid,!preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF: Logarithmic"
                }
                let af = preferences.adjustmentFactor
                let insulin_type = preferences.curve
                let buildDate = Bundle.main.buildDate
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
                if preferences.useCustomPeakTime {
                    iPa = preferences.insulinPeakTime
                } else if preferences.curve.rawValue == "rapid-acting" {
                    iPa = 65
                } else if preferences.curve.rawValue == "ultra-rapid" {
                    iPa = 50
                }
                // CGM Readings
                var glucose_24 = [Readings]() // Day
                var glucose_7 = [Readings]() // Week
                var glucose_30 = [Readings]() // Month
                var glucose = [Readings]() // Total
                let filter = DateFilter()
                // 24h
                let requestGFS_24 = Readings.fetchRequest() as NSFetchRequest<Readings>
                let sortGlucose_24 = NSSortDescriptor(key: "date", ascending: false)
                requestGFS_24.predicate = NSPredicate(format: "glucose > 0 AND date > %@", filter.day)
                requestGFS_24.sortDescriptors = [sortGlucose_24]
                try? glucose_24 = coredataContext.fetch(requestGFS_24)
                // Week
                let requestGFS_7 = Readings.fetchRequest() as NSFetchRequest<Readings>
                let sortGlucose_7 = NSSortDescriptor(key: "date", ascending: false)
                requestGFS_7.predicate = NSPredicate(format: "glucose > 0 AND date > %@", filter.week)
                requestGFS_7.sortDescriptors = [sortGlucose_7]
                try? glucose_7 = coredataContext.fetch(requestGFS_7)
                // Month
                let requestGFS_30 = Readings.fetchRequest() as NSFetchRequest<Readings>
                let sortGlucose_30 = NSSortDescriptor(key: "date", ascending: false)
                requestGFS_30.predicate = NSPredicate(format: "glucose > 0 AND date > %@", filter.month)
                requestGFS_30.sortDescriptors = [sortGlucose_30]
                try? glucose_30 = coredataContext.fetch(requestGFS_30)
                // Total
                let requestGFS = Readings.fetchRequest() as NSFetchRequest<Readings>
                let sortGlucose = NSSortDescriptor(key: "date", ascending: false)
                requestGFS.predicate = NSPredicate(format: "glucose > 0 AND date > %@", filter.total)
                requestGFS.sortDescriptors = [sortGlucose]
                try? glucose = coredataContext.fetch(requestGFS)

                // First date
                let previous = glucose.last?.date ?? Date()
                // Last date (recent)
                let current = glucose.first?.date ?? Date()
                // Total time in days
                let numberOfDays = (current - previous).timeInterval / 8.64E4

                // Get glucose computations for every case
                let oneDayGlucose = glucoseStats(glucose_24)
                let sevenDaysGlucose = glucoseStats(glucose_7)
                let thirtyDaysGlucose = glucoseStats(glucose_30)
                let totalDaysGlucose = glucoseStats(glucose)

                let median = Durations(
                    day: roundDecimal(Decimal(oneDayGlucose.median), 1),
                    week: roundDecimal(Decimal(sevenDaysGlucose.median), 1),
                    month: roundDecimal(Decimal(thirtyDaysGlucose.median), 1),
                    total: roundDecimal(Decimal(totalDaysGlucose.median), 1)
                )

                let overrideHbA1cUnit = settingsManager.settings.overrideHbA1cUnit

                let hbs = Durations(
                    day: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                        roundDecimal(Decimal(oneDayGlucose.ifcc), 1) : roundDecimal(Decimal(oneDayGlucose.ngsp), 1),
                    week: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                        roundDecimal(Decimal(sevenDaysGlucose.ifcc), 1) : roundDecimal(Decimal(sevenDaysGlucose.ngsp), 1),
                    month: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                        roundDecimal(Decimal(thirtyDaysGlucose.ifcc), 1) : roundDecimal(Decimal(thirtyDaysGlucose.ngsp), 1),
                    total: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                        roundDecimal(Decimal(totalDaysGlucose.ifcc), 1) : roundDecimal(Decimal(totalDaysGlucose.ngsp), 1)
                )

                var oneDay_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                var sevenDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                var thirtyDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                var totalDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                // Get TIR computations for every case
                oneDay_ = tir(glucose_24)
                sevenDays_ = tir(glucose_7)
                thirtyDays_ = tir(glucose_30)
                totalDays_ = tir(glucose)

                let tir = Durations(
                    day: roundDecimal(Decimal(oneDay_.TIR), 1),
                    week: roundDecimal(Decimal(sevenDays_.TIR), 1),
                    month: roundDecimal(Decimal(thirtyDays_.TIR), 1),
                    total: roundDecimal(Decimal(totalDays_.TIR), 1)
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
                    low: units == .mmolL ? roundDecimal(settingsManager.settings.low.asMmolL, 1) :
                        roundDecimal(settingsManager.settings.low, 0),
                    high: units == .mmolL ? roundDecimal(settingsManager.settings.high.asMmolL, 1) :
                        roundDecimal(settingsManager.settings.high, 0)
                )
                let TimeInRange = TIRs(
                    TIR: tir,
                    Hypos: hypo,
                    Hypers: hyper,
                    Threshold: range,
                    Euglycemic: normal
                )
                let avgs = Durations(
                    day: roundDecimal(Decimal(oneDayGlucose.average), 1),
                    week: roundDecimal(Decimal(sevenDaysGlucose.average), 1),
                    month: roundDecimal(Decimal(thirtyDaysGlucose.average), 1),
                    total: roundDecimal(Decimal(totalDaysGlucose.average), 1)
                )
                let avg = Averages(Average: avgs, Median: median)
                // Standard Deviations
                let standardDeviations = Durations(
                    day: roundDecimal(Decimal(oneDayGlucose.sd), 1),
                    week: roundDecimal(Decimal(sevenDaysGlucose.sd), 1),
                    month: roundDecimal(Decimal(thirtyDaysGlucose.sd), 1),
                    total: roundDecimal(Decimal(totalDaysGlucose.sd), 1)
                )
                // CV = standard deviation / sample mean x 100
                let cvs = Durations(
                    day: roundDecimal(Decimal(oneDayGlucose.cv), 1),
                    week: roundDecimal(Decimal(sevenDaysGlucose.cv), 1),
                    month: roundDecimal(Decimal(thirtyDaysGlucose.cv), 1),
                    total: roundDecimal(Decimal(totalDaysGlucose.cv), 1)
                )
                let variance = Variance(SD: standardDeviations, CV: cvs)

                // Loops
                var lsr = [LoopStatRecord]()
                let requestLSR = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
                requestLSR.predicate = NSPredicate(
                    format: "interval > 0 AND start > %@",
                    Date().addingTimeInterval(-24.hours.timeInterval) as NSDate
                )
                let sortLSR = NSSortDescriptor(key: "start", ascending: false)
                requestLSR.sortDescriptors = [sortLSR]
                try? lsr = coredataContext.fetch(requestLSR)
                // Compute LoopStats for 24 hours
                let oneDayLoops = loops(lsr)
                let loopstat = LoopCycles(
                    loops: oneDayLoops.loops,
                    errors: oneDayLoops.errors,
                    readings: Int(oneDayGlucose.readings),
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

                // Insulin
                var insulinDistribution = [InsulinDistribution]()
                var insulin = Ins(
                    TDD: 0,
                    bolus: 0,
                    temp_basal: 0,
                    scheduled_basal: 0,
                    total_average: 0
                )
                let requestInsulinDistribution = InsulinDistribution.fetchRequest() as NSFetchRequest<InsulinDistribution>
                let sortInsulin = NSSortDescriptor(key: "date", ascending: false)
                requestInsulinDistribution.sortDescriptors = [sortInsulin]
                try? insulinDistribution = coredataContext.fetch(requestInsulinDistribution)
                insulin = Ins(
                    TDD: roundDecimal(currentTDD, 2),
                    bolus: insulinDistribution.first != nil ? ((insulinDistribution.first?.bolus ?? 0) as Decimal) : 0,
                    temp_basal: insulinDistribution.first != nil ? ((insulinDistribution.first?.tempBasal ?? 0) as Decimal) : 0,
                    scheduled_basal: insulinDistribution
                        .first != nil ? ((insulinDistribution.first?.scheduledBasal ?? 0) as Decimal) : 0,
                    total_average: roundDecimal(tddTotalAverage, 1)
                )

                let hbA1cUnit = !overrideHbA1cUnit ? (units == .mmolL ? "mmol/mol" : "%") : (units == .mmolL ? "%" : "mmol/mol")

                let dailystat = Statistics(
                    created_at: Date(),
                    iPhone: UIDevice.current.getDeviceId,
                    iOS: UIDevice.current.getOSInfo,
                    Build_Version: version ?? "",
                    Build_Number: build ?? "1",
                    Branch: branch,
                    CopyRightNotice: String(copyrightNotice_.prefix(32)),
                    Build_Date: buildDate,
                    Algorithm: algo_,
                    AdjustmentFactor: af,
                    Pump: pump_,
                    CGM: cgm.rawValue,
                    insulinType: insulin_type.rawValue,
                    peakActivityTime: iPa,
                    Carbs_24h: carbTotal,
                    GlucoseStorage_Days: Decimal(roundDouble(numberOfDays, 1)),
                    Statistics: Stats(
                        Distribution: TimeInRange,
                        Glucose: avg,
                        HbA1c: hbs, Units: Units(Glucose: units.rawValue, HbA1c: hbA1cUnit),
                        LoopCycles: loopstat,
                        Insulin: insulin,
                        Variance: variance
                    )
                )
                storage.save(dailystat, as: file)
                nightscout.uploadStatistics(dailystat: dailystat)

                let saveStatsCoreData = StatsData(context: self.coredataContext)
                saveStatsCoreData.lastrun = Date()
                try? self.coredataContext.save()
            }
        }
    }

    private func loopStats(loopStatRecord: LoopStats) {
        coredataContext.perform {
            let nLS = LoopStatRecord(context: self.coredataContext)

            nLS.start = loopStatRecord.start
            nLS.end = loopStatRecord.end ?? Date()
            nLS.loopStatus = loopStatRecord.loopStatus
            nLS.duration = loopStatRecord.duration ?? 0.0
            nLS.interval = loopStatRecord.interval ?? 0.0

            try? self.coredataContext.save()
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

    private func updateStatus() {
        debug(.apsManager, "force update status")
        guard let pump = pumpManager else {
            return
        }

        if let omnipod = pump as? OmnipodPumpManager {
            omnipod.getPodStatus { _ in }
        }
        if let omnipodBLE = pump as? OmniBLEPumpManager {
            omnipodBLE.getPodStatus { _ in }
        }
    }

    private func clearBolusReporter() {
        bolusReporter?.removeObserver(self)
        bolusReporter = nil
        processQueue.asyncAfter(deadline: .now() + 0.5) {
            self.bolusProgress.send(nil)
            self.updateStatus()
        }
    }
}

private extension PumpManager {
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval) -> AnyPublisher<DoseEntry?, Error> {
        Future { promise in
            self.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { error in
                if let error = error {
                    debug(.apsManager, "Temp basal failed: \(unitsPerHour) for: \(duration)")
                    promise(.failure(error))
                } else {
                    debug(.apsManager, "Temp basal succeeded: \(unitsPerHour) for: \(duration)")
                    promise(.success(nil))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func enactBolus(units: Double, automatic: Bool) -> AnyPublisher<DoseEntry?, Error> {
        Future { promise in
            // convert automatic
            let automaticValue = automatic ? BolusActivationType.automatic : BolusActivationType.manualRecommendationAccepted

            self.enactBolus(units: units, activationType: automaticValue) { error in
                if let error = error {
                    debug(.apsManager, "Bolus failed: \(units)")
                    promise(.failure(error))
                } else {
                    debug(.apsManager, "Bolus succeeded: \(units)")
                    promise(.success(nil))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func cancelBolus() -> AnyPublisher<DoseEntry?, Error> {
        Future { promise in
            self.cancelBolus { result in
                switch result {
                case let .success(dose):
                    debug(.apsManager, "Cancel Bolus succeeded")
                    promise(.success(dose))
                case let .failure(error):
                    debug(.apsManager, "Cancel Bolus failed")
                    promise(.failure(error))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func suspendDelivery() -> AnyPublisher<Void, Error> {
        Future { promise in
            self.suspendDelivery { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func resumeDelivery() -> AnyPublisher<Void, Error> {
        Future { promise in
            self.resumeDelivery { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }
}

extension BaseAPSManager: PumpManagerStatusObserver {
    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        let percent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(
            percent: percent,
            voltage: nil,
            string: percent > 10 ? .normal : .low,
            display: status.pumpBatteryChargeRemaining != nil
        )
        storage.save(battery, as: OpenAPS.Monitor.battery)
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
