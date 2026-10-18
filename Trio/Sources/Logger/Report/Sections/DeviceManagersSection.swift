import Foundation
import LoopKit

struct DeviceManagersSection: DiagnosticReportSection {
    let title = "Pump and CGM"
    let order = 30
    let pumpManager: @MainActor() -> DeviceManager?
    let cgmManager: @MainActor() -> DeviceManager?

    private static let descriptionLineLimit = 90

    private struct Snapshot {
        let identifier: String
        let title: String
        let description: String
    }

    func render(window _: DateInterval, into _: URL) async -> String {
        let (pump, cgm) = await MainActor.run {
            (pumpManager().map(Self.snapshot), cgmManager().map(Self.snapshot))
        }
        return [Self.markdown(heading: "Pump", pump), Self.markdown(heading: "CGM", cgm)].joined(separator: "\n\n")
    }

    private static func snapshot(_ manager: DeviceManager) -> Snapshot {
        Snapshot(identifier: manager.pluginIdentifier, title: manager.localizedTitle, description: String(reflecting: manager))
    }

    private static func markdown(heading: String, _ snapshot: Snapshot?) -> String {
        guard let snapshot else { return "### \(heading)\n\n_Not configured_" }
        var description = snapshot.description.components(separatedBy: .newlines)
        if description.count > descriptionLineLimit {
            description = Array(description.prefix(descriptionLineLimit))
            description.append("… truncated, full state in DeviceLog-\(snapshot.identifier).txt")
        }
        return [
            "### \(heading)",
            "",
            "- Plugin: \(snapshot.identifier)",
            "- Name: \(snapshot.title)",
            "",
            ReportFormatting.fenced(description.joined(separator: "\n"))
        ].joined(separator: "\n")
    }
}
