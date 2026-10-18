import Foundation

struct SettingsSection: DiagnosticReportSection {
    let title = "Settings"
    let order = 20
    let settingsManager: SettingsManager?

    private static let groups = [
        ("settings", "Trio settings"),
        ("preferences", "Algorithm preferences"),
        ("pumpSettings", "Pump settings")
    ]

    private struct Snapshot: Encodable {
        let settings: TrioSettings
        let preferences: Preferences
        let pumpSettings: PumpSettings
    }

    func render(window _: DateInterval, into directory: URL) async -> String {
        guard let settingsManager else { return "_Settings unavailable_" }
        let snapshot = Snapshot(
            settings: settingsManager.settings,
            preferences: settingsManager.preferences,
            pumpSettings: settingsManager.pumpSettings
        )
        let encoder = JSONCoding.encoder
        encoder.outputFormatting.insert(.sortedKeys)
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: directory.appendingPathComponent("Settings.json"))
            guard let groups = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "_Settings could not be listed_"
            }
            var lines = ["Full values in Settings.json."]
            for (name, heading) in Self.groups {
                guard let values = groups[name] as? [String: Any] else { continue }
                lines += ["", "### \(heading)", ""]
                lines += values.keys.sorted().map { "- \($0): \(Self.describe(values[$0]))" }
            }
            return lines.joined(separator: "\n")
        } catch {
            return "_Settings could not be encoded: \(error.localizedDescription)_"
        }
    }

    private static func describe(_ value: Any?) -> String {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return number.boolValue ? "true" : "false"
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let .some(value) where JSONSerialization.isValidJSONObject(value):
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
            return data.map { String(decoding: $0, as: UTF8.self) } ?? "-"
        default:
            return "-"
        }
    }
}
