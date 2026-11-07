import Foundation
import LoopKit
import UserNotifications
import WatchKit

/// Reads the phone's CGM directly while the phone shares its configuration (the CGM's Read on Apple Watch setting):
/// the watch builds its own manager from that export, keeps it across launches and shows its readings beside the
/// phone's (as LoopKit/Loop#2545's WatchCGMHost).
@MainActor @Observable final class WatchCGMHost {
    static let shared = WatchCGMHost()

    private static let storageKey = "WatchCGMManager"

    @ObservationIgnored private(set) var cgmManager: (any WatchReadableCGM)?
    @ObservationIgnored private var statusObserver: NSObjectProtocol?
    /// The export's `state` the manager was built from; a different one builds a new manager.
    @ObservationIgnored private var builtFrom: [String: Any]?

    /// For the glucose bubble.
    private(set) var isReadingDirectly = false
    private(set) var sensorStateText: String?
    /// The sensor needs a look; set by its lifecycle and by a reading the sensor marks unreliable.
    private(set) var hasSensorProblem = false
    /// When the watch last asked to be opened for a pairing.
    @ObservationIgnored private var lastPairingNotice: Date?
    private static let pairingNoticeID = WatchAlarms.notificationPrefix + "pairing"
    /// As kristinkand/Trio fb7e6a5ea: often enough to be seen, not a nag through the night.
    private static let pairingNoticeInterval: TimeInterval = 20 * 60

    /// A background refresh this long after each reading re-checks acquisition, in case watchOS froze the app before
    /// it lodged the next connect. Past the G7's 35 s tail clearance, so a connect never lands in its advertising tail.
    static let acquisitionBackstopDelay: TimeInterval = 60

    private init() {
        if let raw = UserDefaults.standard.dictionary(forKey: Self.storageKey), let manager = watchCGMManager(rawValue: raw) {
            builtFrom = raw["builtFrom"] as? [String: Any]
            install(manager)
        }
    }

    /// The phone's settings arrived. Builds a manager when its export names a different sensor or code, lets go of
    /// the sensor when the phone stopped sharing, and otherwise treats it as a wake.
    func update(from state: WatchState) {
        guard state.watchReadsSensor, let data = state.sensorConfiguration,
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let configuration = SharedDeviceConfiguration(rawValue: raw)
        else {
            if cgmManager != nil {
                WatchLogger.shared.info(.data, "The phone stopped sharing its CGM; letting go of the sensor")
                remove()
            }
            return
        }
        if cgmManager != nil, let builtFrom, (builtFrom as NSDictionary).isEqual(to: configuration.state) {
            recheckAcquisition()
            return
        }
        if cgmManager != nil {
            WatchLogger.shared.info(.data, "The phone's CGM changed (a new sensor or code): building the watch's manager again")
        }
        guard let manager = watchCGMManager(adopting: configuration, localState: nil) else {
            WatchLogger.shared.warning(.data, "The phone's CGM (\(configuration.managerIdentifier)) can't be read from the watch")
            return
        }
        WatchLogger.shared.info(.data, "CGM manager built from the phone's configuration (\(configuration.managerIdentifier))")
        remove()
        builtFrom = configuration.state
        install(manager)
        save(manager)
    }

    /// Any wake that is not the sensor's own.
    func recheckAcquisition() {
        cgmManager?.recheckAcquisition()
    }

    private func install(_ manager: any WatchReadableCGM) {
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = self
        cgmManager = manager
        statusObserver = NotificationCenter.default.addObserver(
            forName: type(of: manager).statusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatus() }
        }
        updateStatus()
    }

    private func remove() {
        guard let previous = cgmManager else { return }
        previous.cgmManagerDelegate = nil
        Task { await previous.delete() }
        statusObserver.map(NotificationCenter.default.removeObserver)
        statusObserver = nil
        cgmManager = nil
        builtFrom = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        updateStatus()
    }

    private func save(_ manager: any WatchReadableCGM) {
        var raw = manager.watchRawValue
        raw["builtFrom"] = builtFrom
        UserDefaults.standard.set(raw, forKey: Self.storageKey)
    }

    private func updateStatus() {
        isReadingDirectly = cgmManager != nil
        sensorStateText = cgmManager?.watchSensorStateText
        noteSensorProblem(cgmManager?.watchHasSensorProblem ?? false)
        askToBeOpenedForPairing(cgmManager?.watchNeedsAppInFront ?? false)
    }

    /// A pairing waits for Trio on the screen: in the background, a notification asks for it, and goes once the
    /// pairing has gone through.
    private func askToBeOpenedForPairing(_ needed: Bool) {
        let center = UNUserNotificationCenter.current()
        guard needed else {
            if lastPairingNotice != nil {
                lastPairingNotice = nil
                center.removeDeliveredNotifications(withIdentifiers: [Self.pairingNoticeID])
            }
            return
        }
        guard WKApplication.shared().applicationState != .active,
              (lastPairingNotice ?? .distantPast).addingTimeInterval(Self.pairingNoticeInterval) < Date()
        else { return }
        lastPairingNotice = Date()
        WatchLogger.shared.info(.data, "A sensor pairing waits for Trio on the screen: asking to be opened")
        WatchAlarms.shared.notify(
            id: Self.pairingNoticeID,
            title: String(localized: "Open Trio to Pair the Sensor"),
            body: String(localized: "The watch can only pair with the sensor while Trio is open. Accept a Bluetooth pairing request if one appears.")
        )
    }

    private func noteSensorProblem(_ problem: Bool) {
        hasSensorProblem = problem
    }

    private func scheduleAcquisitionBackstop() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: Self.acquisitionBackstopDelay),
            userInfo: nil
        ) { error in
            if let error {
                WatchLogger.shared.warning(.lifecycle, "Could not schedule the acquisition backstop", error: error)
            }
        }
    }

    private static func direction(_ trend: GlucoseTrend?) -> BloodGlucose.Direction {
        switch trend {
        case .upUpUp: return .doubleUp
        case .upUp: return .singleUp
        case .up: return .fortyFiveUp
        case .flat: return .flat
        case .down: return .fortyFiveDown
        case .downDown: return .singleDown
        case .downDownDown: return .doubleDown
        default: return .none
        }
    }

    /// The watch's own readings in the form the phone sends them.
    static func readings(from samples: [NewGlucoseSample]) -> [BloodGlucose] {
        samples.filter { !$0.wasUserEntered }.map { sample in
            let value = Int(sample.quantity.doubleValue(for: .milligramsPerDeciliter))
            return BloodGlucose(
                id: UUID().uuidString,
                sgv: value,
                direction: direction(sample.trend),
                date: Decimal(Int64(sample.date.timeIntervalSince1970 * 1000)),
                dateString: sample.date,
                unfiltered: Decimal(value),
                glucose: value,
                type: "sgv"
            )
        }
    }
}

extension WatchCGMHost: CGMManagerDelegate {
    nonisolated func startDateToFilterNewData(for _: CGMManager) -> Date? { nil }

    nonisolated func cgmManager(_: CGMManager, hasNew readingResult: CGMReadingResult) {
        MainActor.assumeIsolated {
            switch readingResult {
            case let .newData(samples):
                let readings = Self.readings(from: samples)
                guard !readings.isEmpty else { return }
                WatchLogger.shared.info(.data, "Direct reading: \(readings.count) sample(s)")
                noteSensorProblem(cgmManager?.watchHasSensorProblem ?? false)
                WatchState.shared.applyOwnReadings(readings)
                WatchAlarms.shared.check(own: readings)
                scheduleAcquisitionBackstop()
            case .unreliableData:
                noteSensorProblem(true)
            case let .error(error):
                WatchLogger.shared.warning(.data, "CGM reading failed", error: error)
            case .noData:
                break
            }
        }
    }

    nonisolated func cgmManager(_: CGMManager, hasNew _: [PersistedCgmEvent]) {}

    /// The phone owns the sensor; a manager passed its configuration lets go when the phone stops sharing.
    nonisolated func cgmManagerWantsDeletion(_: CGMManager) async {}

    nonisolated func cgmManagerDidUpdateState(_ manager: CGMManager) {
        MainActor.assumeIsolated {
            guard let cgmManager, manager === cgmManager else { return }
            save(cgmManager)
            updateStatus()
        }
    }

    nonisolated func credentialStoragePrefix(for _: CGMManager) -> String {
        "org.nightscout.Trio.WatchCGMHost"
    }

    nonisolated func cgmManager(_ manager: CGMManager, didUpdate _: CGMManagerStatus) {
        MainActor.assumeIsolated {
            guard let cgmManager, manager === cgmManager else { return }
            updateStatus()
        }
    }

    nonisolated func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type: DeviceLogEntryType,
        message: String,
        completion: ((Error?) -> Void)?
    ) {
        WatchLogger.shared.debug(.data, "CGM \(type): \(message)")
        completion?(nil)
    }

    nonisolated func deviceManager(_: DeviceManager, recordAnalyticsEvent _: String, properties _: [AnyHashable: Any]?) {}

    // The phone issues the sensor's alerts; the watch only logs them.
    nonisolated func issueAlert(_ alert: Alert) async {
        WatchLogger.shared.info(.data, "Alert from the watch's CGM, not shown: \(alert.identifier.value)")
    }

    nonisolated func retractAlert(identifier _: Alert.Identifier) async {}

    nonisolated func doesIssuedAlertExist(identifier _: Alert.Identifier) async throws -> Bool { false }

    nonisolated func lookupAllUnretracted(managerIdentifier _: String) async throws -> [PersistedAlert] { [] }

    nonisolated func lookupAllUnacknowledgedUnretracted(managerIdentifier _: String) async throws -> [PersistedAlert] { [] }

    nonisolated func recordRetractedAlert(_: Alert, at _: Date) async throws {}
}
