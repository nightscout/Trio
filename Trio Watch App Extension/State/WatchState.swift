import Foundation
import SwiftUI
import UserNotifications
import WatchConnectivity
import WidgetKit

/// WatchState manages the communication between the Watch app and the iPhone app using WatchConnectivity.
/// It handles glucose data synchronization and sending treatment requests (bolus, carbs) to the phone.
@Observable final class WatchState: NSObject, WCSessionDelegate {
    /// Shared, not created in a view: the CGM host and the alarms reach it outside any view; one instance keeps the session delegate.
    static let shared = WatchState()

    // MARK: - Properties

    /// The WatchConnectivity session instance used for communication
    var session: WCSession?
    /// Indicates if the paired iPhone is currently reachable
    var isReachable = false

    var lastWatchStateUpdate: TimeInterval?

    /// main view relevant metrics
    var currentGlucose: String = "--"
    var currentGlucoseColorString: String = "#ffffff"
    var trend: String? = ""
    var delta: String? = "--"
    var glucoseValues: [(date: Date, glucose: Double, color: Color)] = []
    var minYAxisValue: Decimal = 39
    var maxYAxisValue: Decimal = 200
    var cob: String? = "--"
    var iob: String? = "--"
    var lastLoopTime: String? = "--"
    /// When the phone last looped; the watch ages it itself.
    var lastLoopDate: Date?
    var overridePresets: [OverridePresetWatch] = []
    var tempTargetPresets: [TempTargetPresetWatch] = []
    var snoozeUntilDate: Date = .distantPast

    /// treatments inputs
    /// used to store carbs for combined meal-bolus-treatments
    var carbsAmount: Int = 0
    var fatAmount: Int = 0
    var proteinAmount: Int = 0
    var bolusAmount: Double = 0.0
    var confirmationProgress: Double = 0.0
    /// Last time the user opened or changed a carbs/bolus entry; nil when no entry is in progress
    @ObservationIgnored private(set) var entryEditedAt: Date?
    /// An entry left alone for longer than this is cleared and never sent
    static let entryLifetime: TimeInterval = 2 * 60
    static let entryExpiredMessage = String(
        localized: "Entry expired after 2 minutes. Nothing was sent. Please enter it again.",
        comment: "Watch message when a carbs or bolus entry was too old to send"
    )

    // Safety limits
    var maxBolus: Decimal = 10
    var maxCarbs: Decimal = 250
    var maxFat: Decimal = 250
    var maxProtein: Decimal = 250

    // Pump specific dosing increment
    var bolusIncrement: Decimal = 0.05
    var confirmBolusFaster: Bool = false

    var complicationCornerValue: WatchComplicationValue = WatchComplicationDefaults.cornerValue
    var complicationSecondaryValue: WatchComplicationValue = WatchComplicationDefaults.secondaryValue
    var complicationStaleMinutes: Int = WatchComplicationDefaults.staleMinutes
    var complicationRingStops: [ComplicationRingStop] = []
    var glucoseUnits: String = ComplicationState.defaultUnits
    var lowGlucoseLimit: Double?
    var highGlucoseLimit: Double?

    // Forecast options
    var showForecast: Bool = false
    var isForecastCone: Bool = false
    var forecastStartDate: Date?
    var forecastConeMin: [Double] = []
    var forecastConeMax: [Double] = []
    var forecastLines: [String: [Double]] = [:] // "iob" / "cob" / "uam" / "zt" -> values

    // Acknowlegement handling
    var showCommsAnimation: Bool = false
    var showAcknowledgmentBanner: Bool = false
    var acknowledgementStatus: AcknowledgementStatus = .pending
    var acknowledgmentMessage: String = ""
    var shouldNavigateToRoot: Bool = true
    @ObservationIgnored private var acknowledgmentTimeoutWorkItem: DispatchWorkItem?

    /// Long enough for a pump to accept a bolus, short enough that the user isn't left guessing
    static let acknowledgmentTimeout: TimeInterval = 15
    static let noAnswerMessage = String(
        localized: "No answer from iPhone. Check Trio on your iPhone before trying again.",
        comment: "Watch message when the phone did not confirm a request"
    )
    static let phoneUnreachableMessage = String(
        localized: "iPhone not reachable. Nothing was sent.",
        comment: "Watch message when a request could not be sent to the phone"
    )
    static let invalidBolusAmountMessage = String(
        localized: "Error! Bolus amount must be greater than 0 U.",
        comment: "Error message when a bolus of zero or less is requested"
    )

    // Bolus calculation progress
    var showBolusCalculationProgress: Bool = false

    // Meal bolus-specific properties
    var mealBolusStep: MealBolusStep = .savingCarbs
    var isMealBolusCombo: Bool = false

    var recommendedBolus: Decimal = 0

    /// Snapshots older than this are dropped at the top of the WC delegate
    /// methods. Single source of truth for `didReceiveMessage`,
    /// `didReceiveUserInfo` and `didReceiveApplicationContext`.
    private static let maxAcceptableMessageAgeInMinutes: TimeInterval = 15 * 60

    /// In memory, so relaunches accept any payload.
    private var lastAcceptedStateDate: Date?

    private static let syncingAnimationTimeout: TimeInterval = 10
    /// Set while a request awaits its reply.
    private var syncTimeout: DispatchWorkItem?

    // MARK: - Debouncing and batch processing helpers

    /// Temporary storage for new data arriving via WatchConnectivity.
    private var pendingData: [String: Any] = [:]
    private var lastSavedComplicationState: ComplicationState?
    private static let maxComplicationHistoryPoints = 40.0

    /// Work item to schedule finalizing the pending data.
    private var finalizeWorkItem: DispatchWorkItem?
    private let complicationReloader = ComplicationReloader(
        fetchInstalledKinds: { completion in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let installedKinds = (try? result.get())?.map(\.kind) ?? []
                DispatchQueue.main.async { completion(installedKinds) }
            }
        },
        reloadTimelines: { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
    )

    /// Debounce only in the foreground.
    private var isAppActive = false

    /// A flag to tell the UI we’re still updating.
    var showSyncingAnimation: Bool = false

    var deviceType = WatchSize.current

    /// Cached from the phone so the setting still applies while the phone is away.
    var useCriticalAlerts: Bool = UserDefaults.standard.bool(forKey: WatchMessageKeys.useCriticalAlertsWatch) {
        didSet {
            UserDefaults.standard.set(useCriticalAlerts, forKey: WatchMessageKeys.useCriticalAlertsWatch)
            if useCriticalAlerts {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .criticalAlert]) { granted, _ in
                    WatchLogger.shared.info(.data, "Critical alerts on: watch notifications allowed=\(granted)")
                }
            }
        }
    }

    /// The last CGM export from the phone. Persisted so the link comes back after watchOS ends the app while the phone
    /// is away; `watchReadsSensor` controls whether the watch uses it.
    var sensorConfiguration: Data? = UserDefaults.standard.data(forKey: WatchMessageKeys.watchSensorConfiguration) {
        didSet { UserDefaults.standard.set(sensorConfiguration, forKey: WatchMessageKeys.watchSensorConfiguration) }
    }

    /// The CGM's Read on Apple Watch, as the phone last sent it.
    var watchReadsSensor: Bool = UserDefaults.standard.bool(forKey: WatchMessageKeys.watchReadsSensor) {
        didSet {
            UserDefaults.standard.set(watchReadsSensor, forKey: WatchMessageKeys.watchReadsSensor)
            if watchReadsSensor != oldValue {
                WatchLogger.shared.info(.data, "Read on Apple Watch: \(watchReadsSensor ? "on" : "off")")
            }
        }
    }

    /// The phone's range, color scheme and alarms, for the watch's own readings; persisted with them.
    var glucoseRange: WatchGlucoseRange = .saved {
        didSet { glucoseRange.save() }
    }

    /// The newest reading the phone has sent.
    private(set) var phoneNewestReading: Date?
    /// The phone's readings and bubble as it sent them, shown while the watch has no fresh reading of its own.
    private var phoneGlucoseValues: [(date: Date, glucose: Double, color: Color)] = []
    private var phoneBubble = PhoneBubble()
    private struct PhoneBubble {
        var currentGlucose = "--"
        var colorString = "#ffffff"
        var trend: String? = ""
        var delta: String? = "--"
    }

    /// Readings from the watch's own sensor link, oldest first, the last six hours.
    private var ownReadings: [BloodGlucose] = []
    /// The reading shown is the watch's own, not the phone's: the bubble says so.
    private(set) var newestReadingIsOwn = false
    /// The watch's own newest reading is shown while it is this fresh: one 5-minute cycle and 30 s of slack. After
    /// that, the phone's readings, if they are newer.
    static let ownReadingFreshFor: TimeInterval = 5 * 60 + 30
    /// Falls back to the phone's readings once the watch's own newest is no longer fresh.
    private var ownReadingExpiry: DispatchWorkItem?

    /// The phone's readings keep coming: one 5-minute cycle and 30 s of slack since its newest, as the watch's own.
    static let phoneReadingsFreshFor: TimeInterval = ownReadingFreshFor

    /// While true, the watch leaves the alarms to the phone.
    func phoneReadingsAreFresh(at now: Date = Date()) -> Bool {
        guard let phoneNewestReading else { return false }
        return now.timeIntervalSince(phoneNewestReading) < Self.phoneReadingsFreshFor
    }

    override init() {
        super.init()
        setupSession()
    }

    func ingestReceivedApplicationContext() {
        guard let context = session?.receivedApplicationContext, !context.isEmpty else { return }
        handleIncomingWatchStatePayload(context)
    }

    var isAwaitingDelivery: Bool {
        guard let session else { return false }
        return session.activationState != .activated || session.hasContentPending || !pendingData.isEmpty ||
            complicationReloader.isReloading
    }

    /// Configures the WatchConnectivity session if supported on the device
    private func setupSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            self.session = session
            if session.activationState == .activated {
                // Already active: no activation callback comes.
                DispatchQueue.main.async {
                    self.handleSessionActivated(session)
                }
            } else {
                session.activate()
            }
            WatchLogger.shared.debug(.connectivity, "Session set up")
        } else {
            WatchLogger.shared.error(.connectivity, "Watch connectivity not supported on this device")
        }
    }

    // MARK: - Entry lifetime

    /// Starts or restarts the entry's clock. Call when an input screen appears and on every amount change.
    func markEntryEdited(at now: Date = Date()) {
        entryEditedAt = now
    }

    /// True only for an entry changed within `entryLifetime`; an entry with no recorded edit is never fresh
    func isEntryFresh(at now: Date = Date()) -> Bool {
        guard let entryEditedAt else { return false }
        return now.timeIntervalSince(entryEditedAt) <= Self.entryLifetime
    }

    /// Ends the entry: clears amounts, the recommendation and the confirmation progress
    func clearEntry() {
        bolusAmount = 0
        carbsAmount = 0
        fatAmount = 0
        proteinAmount = 0
        recommendedBolus = 0
        confirmationProgress = 0
        entryEditedAt = nil
    }

    /// Clears an entry older than `entryLifetime`. Returns true when it did, so the caller can
    /// leave the input screens.
    @discardableResult func expireStaleEntry(at now: Date = Date()) -> Bool {
        guard entryEditedAt != nil, !isEntryFresh(at: now) else { return false }
        WatchLogger.shared.info(.treatments, "Entry older than \(Int(Self.entryLifetime / 60)) min cleared")
        clearEntry()
        return true
    }

    // MARK: – Handle Acknowledgement Messages FROM Phone

    /// Shows "Processing…" and starts the clock for the phone's answer
    func beginAwaitingAcknowledgment(timeout: TimeInterval = WatchState.acknowledgmentTimeout) {
        acknowledgmentTimeoutWorkItem?.cancel()
        acknowledgementStatus = .pending
        showCommsAnimation = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.handleMissingAcknowledgment()
        }
        acknowledgmentTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    /// No answer arrived in time, or sending reported an error. Sending can report an error and
    /// still deliver the request, so this tells the user to check the phone rather than claiming
    /// the request failed.
    func handleMissingAcknowledgment() {
        guard showCommsAnimation else { return }
        WatchLogger.shared.warning(.treatments, "No answer from the phone for the last request")
        handleAcknowledgment(success: false, message: Self.noAnswerMessage)
    }

    /// The request was refused on the watch and never sent
    func handleRequestNotSent(_ message: String) {
        handleAcknowledgment(success: false, message: message)
    }

    func handleAcknowledgment(success: Bool, message: String, isFinal: Bool = true) {
        acknowledgmentTimeoutWorkItem?.cancel()
        acknowledgmentTimeoutWorkItem = nil

        if success {
            acknowledgementStatus = .success
            acknowledgmentMessage = message

            // Hide progress animation
            DispatchQueue.main.async {
                self.showCommsAnimation = false
            }
        } else {
            // Hide progress animation
            DispatchQueue.main.async {
                self.showCommsAnimation = false
            }
            acknowledgementStatus = .failure
            acknowledgmentMessage = "\(message)"
        }

        if isFinal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.showAcknowledgmentBanner = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showAcknowledgmentBanner = false
                self.showSyncingAnimation = false // Just ensure this is 100% set to false
            }
        }
    }

    // MARK: - WCSessionDelegate

    /// Called when the session has completed activation
    /// Updates the reachability status and logs the activation state
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                WatchLogger.shared.error(.connectivity, "Session activation failed", error: error)
                return
            }

            if activationState == .activated {
                WatchLogger.shared.info(.connectivity, "Session activated, phone reachable: \(session.isReachable)")

                WatchBackgroundRefresh.schedule()

                self.handleSessionActivated(session)
            }
        }
    }

    private func handleSessionActivated(_ session: WCSession) {
        isReachable = session.isReachable

        WatchLogger.shared.debug(.connectivity, "Phone reachable after activation: \(session.isReachable)")

        let context = session.receivedApplicationContext
        if !context.isEmpty {
            acceptWatchStatePayload(context)
        }

        forceConditionalWatchStateUpdate()
    }

    func refreshIfNeeded() {
        DispatchQueue.main.async {
            guard let session = self.session, session.activationState == .activated else { return }
            self.forceConditionalWatchStateUpdate()
        }
    }

    /// Handles incoming messages from the paired iPhone when Phone is in the foreground
    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        if WatchLogger.shared.handlePhoneMessage(message) { return }

        // Ack at top level — no `watchState` wrapper, no staleness check.
        if let acknowledged = message[WatchMessageKeys.acknowledged] as? Bool,
           let ackMessage = message[WatchMessageKeys.message] as? String,
           let ackCodeRaw = message[WatchMessageKeys.ackCode] as? String
        {
            if acknowledged {
                WatchLogger.shared.info(.treatments, "Phone confirmed request (\(ackCodeRaw)): \(ackMessage)")
            } else {
                WatchLogger.shared.warning(.treatments, "Phone rejected request (\(ackCodeRaw)): \(ackMessage)")
            }
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
            }
            processWatchMessage(message)
            return
        }

        // Recommended bolus is also not part of the WatchState message.
        if let recommendedBolus = message[WatchMessageKeys.recommendedBolus] as? NSNumber {
            WatchLogger.shared.debug(.bolus, "Bolus recommendation of \(recommendedBolus) U received")
            DispatchQueue.main.async {
                self.recommendedBolus = recommendedBolus.decimalValue
                self.showBolusCalculationProgress = false
            }
            return
        }

        handleIncomingWatchStatePayload(message)
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if WatchLogger.shared.handlePhoneMessage(userInfo) { return }
        handleIncomingWatchStatePayload(userInfo)
    }

    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncomingWatchStatePayload(applicationContext)
    }

    func session(_: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        WatchLogger.shared.transferFinished(fileTransfer, error: error)
    }

    private func handleIncomingWatchStatePayload(_ dictionary: [String: Any]) {
        DispatchQueue.main.async {
            self.acceptWatchStatePayload(dictionary)
        }
    }

    /// Rejections leave the syncing animation alone.
    @discardableResult func acceptWatchStatePayload(_ dictionary: [String: Any]) -> Bool {
        guard let payload = dictionary[WatchMessageKeys.watchState] as? [String: Any],
              let timestamp = payload[WatchMessageKeys.date] as? TimeInterval
        else {
            WatchLogger.shared.warning(.data, "Watch state payload malformed, skipped")
            return false
        }
        let date = Date(timeIntervalSince1970: timestamp)

        // Wall-clock staleness gate. Drops the queued backlog cheaply when
        // the watch app wakes after long disuse; without it, every payload
        // schedules merge + UI work.
        guard date >= Date().addingTimeInterval(-Self.maxAcceptableMessageAgeInMinutes) else {
            if WatchLogger.shared.shouldLog("staleState") {
                WatchLogger.shared.debug(.data, "Stale watch state from \(date) skipped")
            }
            adoptGlucoseValues(fromStale: payload)
            return false
        }

        // Same state via message and context.
        if let lastAccepted = lastAcceptedStateDate, date <= lastAccepted {
            if WatchLogger.shared.shouldLog("duplicateState") {
                WatchLogger.shared.debug(.data, "Duplicate watch state from \(date) skipped")
            }
            return false
        }

        lastAcceptedStateDate = date
        scheduleUIUpdate(with: payload)
        return true
    }

    /// Stale states still bring valid readings. They are the phone's, shown beside the watch's own as any others.
    private func adoptGlucoseValues(fromStale payload: [String: Any]) {
        guard let readings = Self.glucoseValues(from: payload),
              let newest = readings.last?.date,
              newest > phoneNewestReading ?? .distantPast
        else { return }

        WatchLogger.shared.debug(.data, "Glucose readings taken over from a stale watch state")
        phoneGlucoseValues = readings
        phoneNewestReading = newest
        applyOwnOverlay()
    }

    /// The phone's readings, oldest first.
    private static func glucoseValues(from payload: [String: Any]) -> [(date: Date, glucose: Double, color: Color)]? {
        guard let glucoseData = payload[WatchMessageKeys.glucoseValues] as? [[String: Any]] else { return nil }
        return glucoseData.compactMap { data in
            guard let glucose = data["glucose"] as? Double,
                  let timestamp = data["date"] as? TimeInterval,
                  let colorString = data["color"] as? String
            else { return nil }

            return (
                Date(timeIntervalSince1970: timestamp),
                glucose,
                colorString.toColor() // Convert colorString to Color
            )
        }
        .sorted { $0.date < $1.date }
    }

    func session(_: WCSession, didFinish _: WCSessionUserInfoTransfer, error: (any Error)?) {
        if let error = error {
            WatchLogger.shared.warning(.connectivity, "User info transfer to the phone failed", error: error)
        }
    }

    /// Called when the reachability status of the paired iPhone changes
    /// Updates the local reachability status
    func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        DispatchQueue.main.async {
            self.handleReachabilityChange(isReachable: isReachable)
        }
    }

    /// Reachability flips on every wrist raise, so this must leave entries in progress alone:
    /// clearing `bolusAmount` here turned a confirmed bolus into a 0 U request.
    /// The main view resets the entry fields when it appears.
    func handleReachabilityChange(isReachable: Bool) {
        self.isReachable = isReachable
        if WatchLogger.shared.shouldLog("reachability", state: "\(isReachable)") {
            WatchLogger.shared.debug(.connectivity, "Phone reachable: \(isReachable)")
        }

        if isReachable {
            forceConditionalWatchStateUpdate()
        }
    }

    /// Conditionally triggers a watch state update if the last known update was too long ago or has never occurred.
    ///
    /// This method checks the `lastWatchStateUpdate` timestamp to determine how many seconds
    /// have elapsed since the last update under the following conditions
    ///  - If `lastWatchStateUpdate` is `nil` (meaning there has never been an update), or
    ///  - If more than 15 seconds have passed,
    ///
    /// it will show a syncing animation and request a new watch state update from the iPhone app.
    private func forceConditionalWatchStateUpdate() {
        guard let lastUpdateTimestamp = lastWatchStateUpdate else {
            WatchLogger.shared.debug(.data, "No watch state yet, requesting one")

            // If there's no recorded timestamp, we must force a fresh update immediately.
            syncWithPhone()
            return
        }

        let now = Date().timeIntervalSince1970
        let secondsSinceUpdate = now - lastUpdateTimestamp

        // If more than 15 seconds have elapsed since the last update, force an(other) update.
        if secondsSinceUpdate > 15 {
            WatchLogger.shared.debug(.data, "Watch state \(Int(secondsSinceUpdate)) s old, requesting update")
            syncWithPhone()
            return
        }
    }

    private func syncWithPhone() {
        guard syncTimeout == nil, requestWatchStateUpdate() else { return }

        showSyncingAnimation = true
        let timeout = DispatchWorkItem { [self] in
            WatchLogger.shared.debug(.connectivity, "No watch state answer from the phone, syncing animation hidden")
            endSync(hidingAnimation: pendingData.isEmpty)
        }
        syncTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.syncingAnimationTimeout, execute: timeout)
    }

    /// Ends the request in flight.
    func endSync(hidingAnimation: Bool) {
        syncTimeout?.cancel()
        syncTimeout = nil
        if hidingAnimation { showSyncingAnimation = false }
    }

    /// Handles incoming messages that either contain an acknowledgement or fresh watchState data  (<15 min)
    private func processWatchMessage(_ message: [String: Any]) {
        DispatchQueue.main.async {
            // 1) Acknowledgment logic
            if let acknowledged = message[WatchMessageKeys.acknowledged] as? Bool,
               let ackMessage = message[WatchMessageKeys.message] as? String,
               let ackCodeRaw = message[WatchMessageKeys.ackCode] as? String,
               let ackCode = AcknowledgmentCode(rawValue: ackCodeRaw)
            {
                DispatchQueue.main.async {
                    self.showSyncingAnimation = false
                }

                switch ackCode {
                case .savingCarbs:
                    self.isMealBolusCombo = true
                    self.mealBolusStep = .savingCarbs
                    self.showCommsAnimation = true
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: false)
                case .enactingBolus:
                    self.isMealBolusCombo = true
                    self.mealBolusStep = .enactingBolus
                    self.showCommsAnimation = true
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: false)
                case .comboComplete:
                    self.isMealBolusCombo = false
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: true)
                default:
                    self.isMealBolusCombo = false
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: true)
                }
            }

            // 2) Raw watchState data
            if message[WatchMessageKeys.watchState] != nil {
                self.acceptWatchStatePayload(message)
            }
        }
    }

    /// Accumulate new data, set isSyncing, and debounce final update
    private func scheduleUIUpdate(with newData: [String: Any]) {
        pendingData.merge(newData) { _, newVal in newVal }
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil

        // Background: apply now, before suspension.
        guard isAppActive else {
            finalizePendingData()
            return
        }

        // 1) Mark as syncing
        DispatchQueue.main.async {
            self.showSyncingAnimation = true
        }

        // 2) Create and schedule a new finalization
        let workItem = DispatchWorkItem { [self] in
            self.finalizePendingData()
        }
        finalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    /// Applies a pending state before suspension.
    func setAppActive(_ isActive: Bool) {
        isAppActive = isActive
        guard !isActive, finalizeWorkItem != nil else { return }
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil
        finalizePendingData()
    }

    /// Applies all pending data to the watch state in one shot
    private func finalizePendingData() {
        finalizeWorkItem = nil
        guard !pendingData.isEmpty else {
            // If we have no actual data, just end syncing
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
            }
            return
        }

        // Actually set your main UI properties here
        processRawDataForWatchState(pendingData)

        // Clear
        pendingData.removeAll()

        // Done - hide sync animation
        DispatchQueue.main.async {
            self.showSyncingAnimation = false
        }

        WatchLogger.shared.debug(.data, "Watch state applied")
    }

    /// Updates the UI properties
    private func processRawDataForWatchState(_ message: [String: Any]) {
        if let timestamp = message[WatchMessageKeys.date] as? TimeInterval {
            lastWatchStateUpdate = timestamp
        }

        if let currentGlucose = message[WatchMessageKeys.currentGlucose] as? String {
            self.currentGlucose = currentGlucose
            phoneBubble.currentGlucose = currentGlucose
        }

        if let currentGlucoseColorString = message[WatchMessageKeys.currentGlucoseColorString] as? String {
            self.currentGlucoseColorString = currentGlucoseColorString
            phoneBubble.colorString = currentGlucoseColorString
        }

        if let trend = message[WatchMessageKeys.trend] as? String {
            self.trend = trend
            phoneBubble.trend = trend
        }

        if let delta = message[WatchMessageKeys.delta] as? String {
            self.delta = delta
            phoneBubble.delta = delta
        }

        if let iob = message[WatchMessageKeys.iob] as? String {
            self.iob = iob
        }

        if let cob = message[WatchMessageKeys.cob] as? String {
            self.cob = cob
        }

        if let lastLoopTime = message[WatchMessageKeys.lastLoopTime] as? String {
            self.lastLoopTime = lastLoopTime
        }

        if let lastLoopDate = message[WatchMessageKeys.lastLoopDate] as? TimeInterval {
            self.lastLoopDate = lastLoopDate > 0 ? Date(timeIntervalSince1970: lastLoopDate) : nil
        }

        if let glucoseValues = Self.glucoseValues(from: message) {
            self.glucoseValues = glucoseValues
            phoneGlucoseValues = glucoseValues
            phoneNewestReading = glucoseValues.last?.date
        }

        if let minYAxisValue = message[WatchMessageKeys.minYAxisValue] {
            if let decimalValue = (minYAxisValue as? NSNumber)?.decimalValue {
                self.minYAxisValue = decimalValue
            }
        }

        if let maxYAxisValue = message[WatchMessageKeys.maxYAxisValue] {
            if let decimalValue = (maxYAxisValue as? NSNumber)?.decimalValue {
                self.maxYAxisValue = decimalValue
            }
        }

        if let overrideData = message[WatchMessageKeys.overridePresets] as? [[String: Any]] {
            overridePresets = overrideData.compactMap { data in
                guard let name = data["name"] as? String,
                      let isEnabled = data["isEnabled"] as? Bool
                else { return nil }
                return OverridePresetWatch(name: name, isEnabled: isEnabled)
            }
        }

        if let tempTargetData = message[WatchMessageKeys.tempTargetPresets] as? [[String: Any]] {
            tempTargetPresets = tempTargetData.compactMap { data in
                guard let name = data["name"] as? String,
                      let isEnabled = data["isEnabled"] as? Bool
                else { return nil }
                return TempTargetPresetWatch(name: name, isEnabled: isEnabled)
            }
        }

        if let maxBolusValue = message[WatchMessageKeys.maxBolus] {
            if let decimalValue = (maxBolusValue as? NSNumber)?.decimalValue {
                maxBolus = decimalValue
            }
        }

        if let maxCarbsValue = message[WatchMessageKeys.maxCarbs] {
            if let decimalValue = (maxCarbsValue as? NSNumber)?.decimalValue {
                maxCarbs = decimalValue
            }
        }

        if let maxFatValue = message[WatchMessageKeys.maxFat] {
            if let decimalValue = (maxFatValue as? NSNumber)?.decimalValue {
                maxFat = decimalValue
            }
        }

        if let maxProteinValue = message[WatchMessageKeys.maxProtein] {
            if let decimalValue = (maxProteinValue as? NSNumber)?.decimalValue {
                maxProtein = decimalValue
            }
        }

        if let bolusIncrement = message[WatchMessageKeys.bolusIncrement] {
            if let decimalValue = (bolusIncrement as? NSNumber)?.decimalValue {
                // limit minimum to 0.05 to avoid dealing with 0.025 increments
                self.bolusIncrement = max(decimalValue, 0.05)
            }
        }

        if let confirmBolusFaster = message[WatchMessageKeys.confirmBolusFaster] {
            if let booleanValue = confirmBolusFaster as? Bool {
                self.confirmBolusFaster = booleanValue
            }
        }

        if let raw = message[WatchMessageKeys.complicationCornerValue] as? String {
            complicationCornerValue = WatchComplicationValue(rawValue: raw) ?? WatchComplicationDefaults.cornerValue
        }

        if let raw = message[WatchMessageKeys.complicationSecondaryValue] as? String {
            complicationSecondaryValue = WatchComplicationValue(rawValue: raw) ?? WatchComplicationDefaults.secondaryValue
        }

        if let minutes = (message[WatchMessageKeys.complicationStaleMinutes] as? NSNumber)?.intValue {
            complicationStaleMinutes = WatchComplicationDefaults.clampedStaleMinutes(minutes)
        }

        if let units = message[WatchMessageKeys.units] as? String {
            glucoseUnits = units
        }

        if let stops = message[WatchMessageKeys.complicationRingStops] as? [[String: Any]] {
            complicationRingStops = stops.compactMap(ComplicationRingStop.init(payload:))
        }

        if let low = (message[WatchMessageKeys.lowGlucoseLimit] as? NSNumber)?.doubleValue {
            lowGlucoseLimit = low
        }

        if let high = (message[WatchMessageKeys.highGlucoseLimit] as? NSNumber)?.doubleValue {
            highGlucoseLimit = high
        }

        if let showForecast = message[WatchMessageKeys.showForecastWatch] as? Bool {
            self.showForecast = showForecast
        }

        if let isForecastCone = message[WatchMessageKeys.isForecastCone] as? Bool {
            self.isForecastCone = isForecastCone
        }

        if let snoozeTimestamp = message[WatchMessageKeys.snoozeUntilDate] as? TimeInterval {
            snoozeUntilDate = Date(timeIntervalSince1970: snoozeTimestamp)
        }

        if let forecastPayload = message[WatchMessageKeys.forecastData] as? [String: Any] {
            if let startTimestamp = forecastPayload[WatchMessageKeys.forecastStartDate] as? TimeInterval {
                forecastStartDate = Date(timeIntervalSince1970: startTimestamp)
            }
            forecastConeMin = forecastPayload[WatchMessageKeys.forecastConeMin] as? [Double] ?? []
            forecastConeMax = forecastPayload[WatchMessageKeys.forecastConeMax] as? [Double] ?? []
            forecastLines = forecastPayload[WatchMessageKeys.forecastLines] as? [String: [Double]] ?? [:]
        }

        if let critical = message[WatchMessageKeys.useCriticalAlertsWatch] as? Bool, critical != useCriticalAlerts {
            useCriticalAlerts = critical
        }

        if let low = message[WatchMessageKeys.glucoseRangeLow] as? Double,
           let high = message[WatchMessageKeys.glucoseRangeHigh] as? Double
        {
            let range = WatchGlucoseRange(
                low: Decimal(low),
                high: Decimal(high),
                target: (message[WatchMessageKeys.glucoseRangeTarget] as? Double).map { Decimal($0) } ?? glucoseRange.target,
                colorScheme: message[WatchMessageKeys.glucoseColorScheme] as? String ?? glucoseRange.colorScheme,
                isMmol: message[WatchMessageKeys.units] as? String == GlucoseUnits.mmolL.rawValue,
                urgentLowAlarm: (message[WatchMessageKeys.glucoseAlarmUrgentLow] as? Double).map { Decimal($0) } ?? 54,
                // 0: no such alarm on
                lowAlarm: (message[WatchMessageKeys.glucoseAlarmLow] as? Double).flatMap { $0 > 0 ? Decimal($0) : nil },
                highAlarm: (message[WatchMessageKeys.glucoseAlarmHigh] as? Double).flatMap { $0 > 0 ? Decimal($0) : nil }
            )
            if range != glucoseRange { glucoseRange = range }
        }

        // the export can be absent while the phone starts; only Read on Apple Watch turns the link off
        var sensorDidChange = false
        if let watchReadsSensor = message[WatchMessageKeys.watchReadsSensor] as? Bool, watchReadsSensor != self.watchReadsSensor {
            self.watchReadsSensor = watchReadsSensor
            sensorDidChange = true
        }
        if let configuration = message[WatchMessageKeys.watchSensorConfiguration] as? Data, configuration != sensorConfiguration {
            sensorConfiguration = configuration
            sensorDidChange = true
        }
        if sensorDidChange {
            Task { @MainActor in WatchCGMHost.shared.update(from: self) }
        }

        // the watch's own reading first; the phone's only while the watch has none fresh
        applyOwnOverlay()
    }

    // MARK: - The watch's own sensor readings

    /// Readings from the watch's own sensor link: shown first, the phone's only while these are not fresh.
    func applyOwnReadings(_ readings: [BloodGlucose]) {
        let known = Set(ownReadings.map { Int($0.dateString.timeIntervalSince1970 / 60) })
        ownReadings += readings.filter { !known.contains(Int($0.dateString.timeIntervalSince1970 / 60)) }
        ownReadings.sort { $0.dateString < $1.dateString }
        applyOwnOverlay()
    }

    /// Picks the reading shown again, as time passes: called when the watch app comes to the front.
    func refreshShownReading() {
        applyOwnOverlay()
    }

    /// The watch's own newest reading is shown while it is fresh (`ownReadingFreshFor`), or while it is newer than the
    /// phone's; otherwise the phone's readings stand as sent. The chart is the watch's own readings, the phone's where
    /// the watch has none. Idempotent: built each time from the phone's copy and the watch's own.
    private func applyOwnOverlay(now: Date = Date()) {
        // the watch's own reading gives way to the phone's once it is no longer fresh
        defer {
            scheduleOwnReadingExpiry(now: now)
            saveComplicationSnapshot()
        }
        ownReadings.removeAll { $0.dateString < now.addingTimeInterval(-6 * 60 * 60) }
        let range = glucoseRange
        let own = ownReadings.compactMap { reading in (reading.glucose ?? reading.sgv).map { (reading, $0) } }
        let phoneNewest = phoneNewestReading ?? .distantPast
        guard let (latest, value) = own.last,
              now.timeIntervalSince(latest.dateString) < Self.ownReadingFreshFor ||
              latest.dateString > phoneNewest.addingTimeInterval(60)
        else {
            showPhoneReadings()
            return
        }
        newestReadingIsOwn = true
        // the phone's copy of a reading carries a timestamp a few seconds apart from the watch's
        let ownDates = own.map(\.0.dateString)
        let phoneOnly = phoneGlucoseValues.filter { phone in
            !ownDates.contains { abs($0.timeIntervalSince(phone.date)) < 150 }
        }
        glucoseValues = (phoneOnly + own.map { (date: $0.0.dateString, glucose: range.display($0.1), color: range.color($0.1)) })
            .sorted { $0.date < $1.date }
        currentGlucose = Decimal(value).formatted(for: range.isMmol ? .mmolL : .mgdL)
        let inRange = Decimal(value) > range.low && Decimal(value) < range.high
        currentGlucoseColorString = inRange ? "#ffffff" : range.color(value).toHexString()
        trend = latest.direction?.rawValue
        if glucoseValues.count >= 2 {
            let change = glucoseValues[glucoseValues.count - 1].glucose - glucoseValues[glucoseValues.count - 2].glucose
            let formatted = range.isMmol ? String(format: "%.1f", change) : String(format: "%.0f", change)
            delta = change < 0 ? formatted : "+" + formatted
        }
    }

    private func showPhoneReadings() {
        newestReadingIsOwn = false
        glucoseValues = phoneGlucoseValues
        currentGlucose = phoneBubble.currentGlucose
        currentGlucoseColorString = phoneBubble.colorString
        trend = phoneBubble.trend
        delta = phoneBubble.delta
    }

    /// While the watch's own reading is shown, the phone's take over once it is no longer fresh, without waiting for
    /// the next reading or phone message.
    private func scheduleOwnReadingExpiry(now: Date) {
        ownReadingExpiry?.cancel()
        ownReadingExpiry = nil
        guard newestReadingIsOwn, let latest = ownReadings.last?.dateString else { return }
        let delay = latest.addingTimeInterval(Self.ownReadingFreshFor).timeIntervalSince(now)
        guard delay > 0 else { return }
        let work = DispatchWorkItem { [weak self] in self?.applyOwnOverlay() }
        ownReadingExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1, execute: work)
    }
}

/// The phone's glucose range, color scheme and alarms, in mg/dL, as `BaseWatchManager` colors the readings it sends.
struct WatchGlucoseRange: Codable, Equatable {
    private static let storageKey = "watchGlucoseRange"

    static var saved: WatchGlucoseRange {
        UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(WatchGlucoseRange.self, from: $0) } ?? WatchGlucoseRange()
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.storageKey)
    }

    var low: Decimal = 70
    var high: Decimal = 180
    var target: Decimal = 100
    var colorScheme: String = GlucoseColorScheme.staticColor.rawValue
    var isMmol = false
    /// The phone's glucose alarms, the most cautious that is on: the watch alarms by them on its own readings.
    var urgentLowAlarm: Decimal = 54
    var lowAlarm: Decimal?
    var highAlarm: Decimal?

    init(
        low: Decimal = 70,
        high: Decimal = 180,
        target: Decimal = 100,
        colorScheme: String = GlucoseColorScheme.staticColor.rawValue,
        isMmol: Bool = false,
        urgentLowAlarm: Decimal = 54,
        lowAlarm: Decimal? = nil,
        highAlarm: Decimal? = nil
    ) {
        self.low = low
        self.high = high
        self.target = target
        self.colorScheme = colorScheme
        self.isMmol = isMmol
        self.urgentLowAlarm = urgentLowAlarm
        self.lowAlarm = lowAlarm
        self.highAlarm = highAlarm
    }

    /// Field by field: a value saved before a field was added keeps the rest.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WatchGlucoseRange()
        low = try container.decodeIfPresent(Decimal.self, forKey: .low) ?? defaults.low
        high = try container.decodeIfPresent(Decimal.self, forKey: .high) ?? defaults.high
        target = try container.decodeIfPresent(Decimal.self, forKey: .target) ?? defaults.target
        colorScheme = try container.decodeIfPresent(String.self, forKey: .colorScheme) ?? defaults.colorScheme
        isMmol = try container.decodeIfPresent(Bool.self, forKey: .isMmol) ?? defaults.isMmol
        urgentLowAlarm = try container.decodeIfPresent(Decimal.self, forKey: .urgentLowAlarm) ?? defaults.urgentLowAlarm
        lowAlarm = try container.decodeIfPresent(Decimal.self, forKey: .lowAlarm)
        highAlarm = try container.decodeIfPresent(Decimal.self, forKey: .highAlarm)
    }

    func display(_ mgdl: Int) -> Double {
        isMmol ? NSDecimalNumber(decimal: Decimal(mgdl).asMmolL).doubleValue : Double(mgdl)
    }

    /// As `BaseWatchManager.setupWatchState`: the dynamic scheme ramps between fixed ends around the target.
    func color(_ mgdl: Int) -> Color {
        let scheme = GlucoseColorScheme(rawValue: colorScheme) ?? .staticColor
        let isDynamic = scheme == .dynamicColor
        return getDynamicGlucoseColor(
            glucoseValue: Decimal(mgdl),
            highGlucoseColorValue: isDynamic ? 220 : high,
            lowGlucoseColorValue: isDynamic ? 55 : low,
            targetGlucose: target,
            glucoseColorScheme: scheme
        )
    }
}

extension WatchState {
    private func saveComplicationSnapshot() {
        guard let latestReading = glucoseValues.last else { return }
        let snapshot = complicationSnapshot(readingDate: latestReading.date, glucoseValue: latestReading.glucose)
        guard snapshot != lastSavedComplicationState else { return }
        do {
            try ComplicationStore.save(snapshot)
            lastSavedComplicationState = snapshot
            reloadInstalledComplications()
            let readingAge = Int(Date().timeIntervalSince(latestReading.date) / 60)
            WatchLogger.shared.info(.data, "Complication snapshot saved, reading \(readingAge) min old")
        } catch {
            WatchLogger.shared.warning(.data, "Complication snapshot not saved", error: error)
        }
    }

    private func complicationSnapshot(readingDate: Date, glucoseValue: Double) -> ComplicationState {
        ComplicationState(
            date: readingDate,
            glucose: currentGlucose,
            glucoseColorHex: currentGlucoseColorString,
            trend: trend ?? "",
            delta: ComplicationState.presentOrMissing(delta),
            iob: ComplicationState.presentOrMissing(iob),
            cob: ComplicationState.presentOrMissing(cob),
            lastLoopTime: ComplicationState.presentOrMissing(lastLoopTime),
            cornerValue: complicationCornerValue,
            secondaryValue: complicationSecondaryValue,
            staleMinutes: complicationStaleMinutes,
            units: glucoseUnits,
            glucoseValue: glucoseValue,
            history: complicationHistory(until: readingDate),
            loopDate: lastLoopDate,
            limits: complicationLimits,
            ringStops: complicationRingStops.isEmpty ? nil : complicationRingStops
        )
    }

    private var complicationLimits: ClosedRange<Double>? {
        guard let low = lowGlucoseLimit, let high = highGlucoseLimit, low < high else { return nil }
        return low ... high
    }

    private func reloadInstalledComplications() {
        complicationReloader.reload(Set(ComplicationKind.allCases.map(\.widgetKind)))
    }

    private func complicationHistory(until end: Date) -> [ComplicationPoint] {
        let from = end.addingTimeInterval(-ComplicationState.chartWindow)
        let recent = glucoseValues.filter { $0.date >= from }
        let step = max(1, Int((Double(recent.count) / Self.maxComplicationHistoryPoints).rounded(.up)))
        return recent.enumerated()
            .filter { $0.offset % step == 0 || $0.offset == recent.count - 1 }
            .map { ComplicationPoint(timestamp: $0.element.date.timeIntervalSince1970, glucose: $0.element.glucose) }
    }
}
