import Foundation

struct DeviceLogSection: DiagnosticReportSection {
    let title = "Device log"
    let order = 100
    let exporter: DeviceLogExporting?

    private static let tailLines = 100

    func render(window: DateInterval, into directory: URL) async -> String {
        guard let exporter else { return "_Device log unavailable_" }
        var lines: [String] = []
        do {
            try await exporter.export(
                DeviceLogExportRequest(window: window, managerIdentifier: nil, includeOSLog: true, includeKitFiles: true),
                into: directory
            )
        } catch {
            lines.append("Export stopped early: \(error.localizedDescription)")
        }

        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        let deviceLogs = files.filter { $0.hasPrefix("DeviceLog-") && $0.hasSuffix(".txt") }
        let others = files.filter { !deviceLogs.contains($0) }
        if !others.isEmpty {
            lines.append("Also attached: \(others.joined(separator: ", ")).")
        }
        guard !deviceLogs.isEmpty else { return (lines + ["", "_No pump or CGM device log_"]).joined(separator: "\n") }

        for name in deviceLogs {
            let url = directory.appendingPathComponent(name)
            let entries = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("* ") }
            lines += ["", "### \(name)", ""]
            if entries.isEmpty {
                lines.append("_No entries in window_")
            } else {
                lines.append("Last \(min(entries.count, Self.tailLines)) of \(entries.count) entries:")
                lines += ["", ReportFormatting.fenced(entries.suffix(Self.tailLines).joined(separator: "\n"))]
            }
        }
        return lines.joined(separator: "\n")
    }
}
