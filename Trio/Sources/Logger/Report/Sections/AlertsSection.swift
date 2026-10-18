import Foundation

struct AlertsSection: DiagnosticReportSection {
    let title = "Alerts"
    let order = 40
    var defaults: UserDefaults = .standard

    // Read-only view of BaseAlertHistoryStorage's persisted history
    static let historyKey = "openaps.monitor.alertHistory.data"
    private static let limit = 200

    func render(window: DateInterval, into _: URL) async -> String {
        guard let data = defaults.data(forKey: Self.historyKey),
              let alerts = try? JSONCoding.decoder.decode([AlertEntry].self, from: data)
        else { return "_No alert history_" }
        let inWindow = alerts.filter { window.contains($0.issuedDate) }.sorted { $0.issuedDate > $1.issuedDate }
        guard !inWindow.isEmpty else { return "_No alerts in window (Trio keeps 24 hours of alert history)_" }
        var lines = ["Trio keeps 24 hours of alert history. Newest first."]
        lines.append("")
        lines += inWindow.prefix(Self.limit).map(Self.line)
        if inWindow.count > Self.limit {
            lines.append("- … \(inWindow.count - Self.limit) older alerts omitted")
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ alert: AlertEntry) -> String {
        var parts = [
            ReportFormatting.timestamp(alert.issuedDate),
            "\(alert.managerIdentifier)/\(alert.alertIdentifier)",
            "trigger \(alert.triggerType)"
        ]
        let content = [alert.contentTitle, alert.contentBody].compactMap { $0 }.joined(separator: ": ")
        if !content.isEmpty {
            parts.append(content.replacingOccurrences(of: "\n", with: " "))
        }
        parts.append(alert.acknowledgedDate.map { "acknowledged \(ReportFormatting.timestamp($0))" } ?? "unacknowledged")
        if let error = alert.errorMessage {
            parts.append("error: \(error)")
        }
        return "- " + parts.joined(separator: " · ")
    }
}
