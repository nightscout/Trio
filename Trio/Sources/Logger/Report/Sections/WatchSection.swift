import Foundation
import WatchConnectivity

struct WatchSection: DiagnosticReportSection {
    let title = "Apple Watch"
    let order = 80

    func render(window _: DateInterval, into _: URL) async -> String {
        guard WCSession.isSupported() else { return "_Watch connectivity not supported on this device_" }
        let session = WCSession.default
        var lines = ["- Session: \(Self.label(for: session.activationState))"]
        // Pairing properties are only valid once the session is activated
        if session.activationState == .activated {
            lines += [
                "- Paired: \(session.isPaired ? "yes" : "no")",
                "- Watch app installed: \(session.isWatchAppInstalled ? "yes" : "no")",
                "- Reachable: \(session.isReachable ? "yes" : "no")",
                "- Complication enabled: \(session.isComplicationEnabled ? "yes" : "no")",
                "- Outstanding transfers: \(session.outstandingUserInfoTransfers.count)"
            ]
        }
        return lines.joined(separator: "\n")
    }

    private static func label(for state: WCSessionActivationState) -> String {
        switch state {
        case .activated: return "activated"
        case .inactive: return "inactive"
        case .notActivated: return "not activated"
        @unknown default: return "unknown"
        }
    }
}
