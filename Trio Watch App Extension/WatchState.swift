import Foundation
import SwiftUI
import UserNotifications
import WatchConnectivity

/// WatchState manages the communication between the Watch app and the iPhone app using WatchConnectivity.
/// It handles glucose data synchronization and sending treatment requests (bolus, carbs) to the phone.
@Observable final class WatchState: NSObject, WCSessionDelegate {
    /// Shared, not created in a view: the CGM host and the alarms reach it outside any view.
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

    // Safety limits
    var maxBolus: Decimal = 10
    var maxCarbs: Decimal = 250
    var maxFat: Decimal = 250
    var maxProtein: Decimal = 250

    // Pump specific dosing increment
    var bolusIncrement: Decimal = 0.05
    var confirmBolusFaster: Bool = false

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

    // Bolus calculation progress
    var showBolusCalculationProgress: Bool = false

    // Meal bolus-specific properties
    var mealBolusStep: MealBolusStep = .savingCarbs
    var isMealBolusCombo: Bool = false

    var recommendedBolus: Decimal = 0

    /// Snapshots older than this are dropped at the top of the WC delegate
    /// methods. Single source of truth for both `didReceiveMessage` and
    /// `didReceiveUserInfo`.
    private static let maxAcceptableMessageAgeInMinutes: TimeInterval = 15 * 60

    // MARK: - Debouncing and batch processing helpers

    /// Temporary storage for new data arriving via WatchConnectivity.
    private var pendingData: [String: Any] = [:]

    /// Work item to schedule finalizing the pending data.
    private var finalizeWorkItem: DispatchWorkItem?

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
    /// Readings from the watch's own sensor link the phone hasn't sent yet, oldest first. Collected all the time, so
    /// they show at once when the phone's readings stop.
    private var ownReadings: [BloodGlucose] = []
    /// The reading shown is the watch's own, not the phone's: the bubble says so.
    private(set) var newestReadingIsOwn = false

    /// The phone's readings keep coming: one 5-minute cycle and the delivery's slack since its newest.
    static let phoneReadingsFreshFor: TimeInterval = 7 * 60

    /// While true, the watch shows only the phone's readings and leaves the alarms to it.
    func phoneReadingsAreFresh(at now: Date = Date()) -> Bool {
        guard let phoneNewestReading else { return false }
        return now.timeIntervalSince(phoneNewestReading) < Self.phoneReadingsFreshFor
    }

    override init() {
        super.init()
        setupSession()
    }

    /// Configures the WatchConnectivity session if supported on the device
    private func setupSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            self.session = session
            WatchLogger.shared.debug(.connectivity, "Session set up")
        } else {
            WatchLogger.shared.error(.connectivity, "Watch connectivity not supported on this device")
        }
    }

    // MARK: – Handle Acknowledgement Messages FROM Phone

    func handleAcknowledgment(success: Bool, message: String, isFinal: Bool = true) {
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

                self.forceConditionalWatchStateUpdate()

                self.isReachable = session.isReachable
            }
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

    func session(_: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        WatchLogger.shared.transferFinished(fileTransfer, error: error)
    }

    /// Shared path for watch-state payloads from either delegate method.
    /// Enforces the freshness contract in one place so the two delivery paths
    /// can't drift.
    private func handleIncomingWatchStatePayload(_ dictionary: [String: Any]) {
        guard let payload = dictionary[WatchMessageKeys.watchState] as? [String: Any],
              let timestamp = payload[WatchMessageKeys.date] as? TimeInterval
        else {
            WatchLogger.shared.warning(.data, "Watch state payload malformed, skipped")
            DispatchQueue.main.async { self.showSyncingAnimation = false }
            return
        }
        let date = Date(timeIntervalSince1970: timestamp)

        // Wall-clock staleness gate. Drops the queued backlog cheaply when
        // the watch app wakes after long disuse; without it, every payload
        // schedules merge + UI work.
        guard date >= Date().addingTimeInterval(-Self.maxAcceptableMessageAgeInMinutes) else {
            if WatchLogger.shared.shouldLog("staleState") {
                WatchLogger.shared.debug(.data, "Stale watch state from \(date) skipped")
            }
            DispatchQueue.main.async { self.showSyncingAnimation = false }
            return
        }

        // Monotonicity dedup.
        let lastProcessed = WatchStateSnapshot.loadLatestDateFromDisk()
        guard date > lastProcessed else {
            if WatchLogger.shared.shouldLog("duplicateState") {
                WatchLogger.shared.debug(.data, "Duplicate watch state from \(date) skipped")
            }
            return
        }

        WatchStateSnapshot.saveLatestDateToDisk(date)
        DispatchQueue.main.async {
            self.scheduleUIUpdate(with: payload)
        }
    }

    func session(_: WCSession, didFinish _: WCSessionUserInfoTransfer, error: (any Error)?) {
        if let error = error {
            WatchLogger.shared.warning(.connectivity, "User info transfer to the phone failed", error: error)
        }
    }

    /// Called when the reachability status of the paired iPhone changes
    /// Updates the local reachability status
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            if WatchLogger.shared.shouldLog("reachability", state: "\(session.isReachable)") {
                WatchLogger.shared.debug(.connectivity, "Phone reachable: \(session.isReachable)")
            }

            if session.isReachable {
                self.forceConditionalWatchStateUpdate()

                // reset input amounts
                self.bolusAmount = 0
                self.carbsAmount = 0

                // reset auth progress
                self.confirmationProgress = 0
            }
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
            showSyncingAnimation = true
            requestWatchStateUpdate()
            return
        }

        let now = Date().timeIntervalSince1970
        let secondsSinceUpdate = now - lastUpdateTimestamp

        // If more than 15 seconds have elapsed since the last update, force an(other) update.
        if secondsSinceUpdate > 15 {
            WatchLogger.shared.debug(.data, "Watch state \(Int(secondsSinceUpdate)) s old, requesting update")
            showSyncingAnimation = true
            requestWatchStateUpdate()
            return
        }
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
            if let watchStateData = message[WatchMessageKeys.watchState] as? [String: Any] {
                self.scheduleUIUpdate(with: watchStateData)
            }
        }
    }

    /// Accumulate new data, set isSyncing, and debounce final update
    private func scheduleUIUpdate(with newData: [String: Any]) {
        if let incomingTimestamp = newData[WatchMessageKeys.date] as? TimeInterval,
           let lastTimestamp = lastWatchStateUpdate,
           incomingTimestamp <= lastTimestamp
        {
            WatchLogger.shared.debug(.data, "Outdated watch state skipped")
            return
        }

        // 1) Mark as syncing
        DispatchQueue.main.async {
            self.showSyncingAnimation = true
        }

        // 2) Merge data into our pendingData
        pendingData.merge(newData) { _, newVal in newVal }

        // 3) Cancel any previous finalization
        finalizeWorkItem?.cancel()

        // 4) Create and schedule a new finalization
        let workItem = DispatchWorkItem { [self] in
            self.finalizePendingData()
        }
        finalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    /// Applies all pending data to the watch state in one shot
    private func finalizePendingData() {
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
        }

        if let currentGlucoseColorString = message[WatchMessageKeys.currentGlucoseColorString] as? String {
            self.currentGlucoseColorString = currentGlucoseColorString
        }

        if let trend = message[WatchMessageKeys.trend] as? String {
            self.trend = trend
        }

        if let delta = message[WatchMessageKeys.delta] as? String {
            self.delta = delta
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

        if let glucoseData = message[WatchMessageKeys.glucoseValues] as? [[String: Any]] {
            glucoseValues = glucoseData.compactMap { data in
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

        // the phone's readings first; the watch's own only once those have stopped
        applyOwnOverlay()
    }

    // MARK: - The watch's own sensor readings

    /// Readings from the watch's own sensor link, always collected; shown only while the phone's have stopped.
    func applyOwnReadings(_ readings: [BloodGlucose]) {
        let known = Set(ownReadings.map { Int($0.dateString.timeIntervalSince1970 / 60) })
        ownReadings += readings.filter { !known.contains(Int($0.dateString.timeIntervalSince1970 / 60)) }
        ownReadings.sort { $0.dateString < $1.dateString }
        applyOwnOverlay()
    }

    /// While the phone's readings come, they stand as sent. Once they stop, the watch's own newer readings follow
    /// them and the newest is the one shown. Idempotent: the phone's next state replaces all of it.
    private func applyOwnOverlay(now: Date = Date()) {
        let phoneNewest = phoneNewestReading ?? .distantPast
        // the phone's copy of a reading carries a timestamp a few seconds apart from the watch's
        ownReadings.removeAll {
            $0.dateString <= phoneNewest.addingTimeInterval(60) || $0.dateString < now.addingTimeInterval(-6 * 60 * 60)
        }
        newestReadingIsOwn = false
        guard !phoneReadingsAreFresh(at: now) else { return }
        glucoseValues.removeAll { $0.date > phoneNewest.addingTimeInterval(60) }
        let range = glucoseRange
        let own = ownReadings.compactMap { reading in (reading.glucose ?? reading.sgv).map { (reading, $0) } }
        guard let (latest, value) = own.last else { return }
        newestReadingIsOwn = true
        glucoseValues += own.map { (date: $0.0.dateString, glucose: range.display($0.1), color: range.color($0.1)) }
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
