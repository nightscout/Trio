import Foundation
import LoopKit

// MARK: - Restored watch alerts

extension BaseSmartwatchHost {
    /// When to clear glucose alerts the plugin restored from before a relaunch.
    /// Trio keeps which alarms are firing in memory only: after a relaunch it
    /// issues an alarm that still applies again once its launch quiet window is
    /// over, but never retracts one that ended while it wasn't running. So the
    /// host waits for a glucose update after the quiet window, and one at least a
    /// minute after that, then retracts every glucose alarm it hasn't forwarded
    /// since launch. The plugin ignores alerts it doesn't have.
    struct RestoredWatchAlerts {
        /// `GlucoseAlertCoordinator`'s launch quiet window.
        static let launchQuietWindow: TimeInterval = 30
        /// Time Trio gets after its first update to issue again what still applies.
        static let reissueTime: TimeInterval = 60

        let launchedAt: Date
        /// Glucose alerts forwarded since launch and not retracted, by `Alert.Identifier.value`.
        var forwarded: Set<String> = []
        private(set) var isCleared = false
        private var firstUpdateAfterQuietWindow: Date?

        init(launchedAt: Date) {
            self.launchedAt = launchedAt
        }

        /// Called on each glucose update; true once, when it's time to clear.
        mutating func glucoseDidUpdate(at now: Date) -> Bool {
            guard !isCleared, now.timeIntervalSince(launchedAt) >= Self.launchQuietWindow else { return false }
            guard let first = firstUpdateAfterQuietWindow else {
                firstUpdateAfterQuietWindow = now
                return false
            }
            guard now.timeIntervalSince(first) >= Self.reissueTime else { return false }
            isCleared = true
            return true
        }

        /// Of the glucose alarms' alerts, those to retract: the ones not forwarded since launch.
        func toRetract(alarmAlerts: [String]) -> [String] {
            alarmAlerts.filter { !forwarded.contains($0) }
        }
    }

    @MainActor func clearRestoredAlertsIfDue() {
        guard let manager = smartwatchManager, restoredAlerts.glucoseDidUpdate(at: Date()) else { return }
        let alarmAlerts = GlucoseAlertsStore.shared.alerts
            .map { GlucoseAlertCoordinator.alertID(for: $0) }
            .filter { Self.glucoseAlertType(of: $0) != nil }
        let toRetract = Set(restoredAlerts.toRetract(alarmAlerts: alarmAlerts.map(\.value)))
        for identifier in alarmAlerts where toRetract.contains(identifier.value) {
            manager.watchAlertDidRetract(identifier)
        }
    }
}

// MARK: - TrioAlertForwarder

extension BaseSmartwatchHost: TrioAlertForwarder {
    /// Which glucose alert this is: Trio's glucose alerts are
    /// `Trio.glucose.<type>.<UUID>`. Carbs-required and every other alert are nil.
    static func glucoseAlertType(of identifier: Alert.Identifier) -> SmartwatchGlucoseAlertType? {
        guard identifier.managerIdentifier == BaseTrioAlertManager.managerIdentifier else { return nil }
        let parts = identifier.alertIdentifier.split(separator: ".")
        guard parts.count >= 2, parts[0] == "glucose" else { return nil }
        switch parts[1] {
        case "urgentLow": return .urgentLow
        case "low": return .low
        case "high": return .high
        case "forecastedLow": return .predictedLow
        default: return nil
        }
    }

    /// Forwards Trio's immediate glucose alerts. Trio's mute drops non-critical
    /// alerts before they get here, so critical ones reach the watch while muted,
    /// as they reach the phone.
    func alertManager(didIssue alert: Alert, muted _: Bool) {
        guard let manager = smartwatchManager else { return }
        // Trio hands every alert to its forwarders; the watch only gets glucose
        // alerts as they fire. Others (and scheduled ones, such as the not-looping
        // ladder Trio re-arms on every loop) are dropped without a log line.
        guard let glucoseAlertType = Self.glucoseAlertType(of: alert.identifier) else { return }
        guard case .immediate = alert.trigger else {
            log(manager, .delegate, "\(alert.identifier.alertIdentifier) not sent to the watch: a scheduled glucose alert")
            return
        }
        let issuedAt = Date()
        Task { @MainActor in
            self.restoredAlerts.forwarded.insert(alert.identifier.value)
            manager.watchAlertDidIssue(alert, glucoseAlertType: glucoseAlertType, issuedAt: issuedAt)
        }
    }

    func alertManager(didRetract identifier: Alert.Identifier) {
        guard let manager = smartwatchManager, Self.glucoseAlertType(of: identifier) != nil else { return }
        Task { @MainActor in
            self.restoredAlerts.forwarded.remove(identifier.value)
            manager.watchAlertDidRetract(identifier)
        }
    }
}
