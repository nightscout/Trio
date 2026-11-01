import Foundation

struct LogFileHeader {
    struct Device {
        let title: String
        let identifier: String
        let description: String
    }

    var kind: LogExport.Kind
    var days: Int
    var created: Date
    var pump: Device?
    var cgm: Device?
    var settings: [String] = []
    var alerts: [AlertEntry] = []

    private static let alertLimit = 200

    var title: String {
        switch kind {
        case .all: return "Trio Logs"
        case .pump: return "Trio Pump Logs"
        case .cgm: return "Trio CGM Logs"
        }
    }

    var text: String {
        let formatter = LogFileWriter.timestampFormatter(milliseconds: false)
        var lines = [
            title,
            "Created: \(formatter.string(from: created))",
            "Covers: last \(days == 1 ? "24 hours" : "\(days) days")",
            "Personal details such as your Nightscout address, passwords and device serial numbers have been removed."
        ]
        lines += Self.section("App", Self.app())
        lines += Self.section("Phone", Self.phone())
        if kind != .cgm {
            lines += Self.section("Pump", Self.lines(for: pump))
        }
        if kind != .pump {
            lines += Self.section("CGM", Self.lines(for: cgm))
        }
        if kind == .all {
            lines += Self.section("Settings", settings.isEmpty ? ["Not available"] : settings)
            lines += Self.section("Alerts", alertLines(formatter: formatter))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func section(_ name: String, _ lines: [String]) -> [String] {
        ["", "== \(name) =="] + lines
    }

    private static func app() -> [String] {
        let bundle = Bundle.main
        let details = BuildDetails.shared
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        var lines = [
            "Trio: \(version) (\(build)), dev version \(bundle.appDevVersion ?? "unknown")",
            "Branch: \(details.trioBranch)",
            "Commit: \(details.trioCommitSHA)",
            "Built: \(details.buildDateString ?? "unknown")"
        ]
        lines += details.submodules.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.branch) \($0.value.commitSHA)" }
        return lines
    }

    private static func phone() -> [String] {
        let processInfo = ProcessInfo.processInfo
        return [
            "iOS: \(processInfo.operatingSystemVersionString)",
            "Model: \(modelIdentifier)",
            "Low Power Mode: \(processInfo.isLowPowerModeEnabled ? "on" : "off")",
            "Free storage: \(freeStorage)"
        ]
    }

    private static func lines(for device: Device?) -> [String] {
        guard let device else { return ["Not set up"] }
        return ["Name: \(device.title)", "Plugin: \(device.identifier)", device.description]
    }

    private func alertLines(formatter: DateFormatter) -> [String] {
        let newestFirst = alerts.sorted { $0.issuedDate > $1.issuedDate }
        guard !newestFirst.isEmpty else { return ["None"] }
        var lines = newestFirst.prefix(Self.alertLimit).map { alert in
            var parts = [formatter.string(from: alert.issuedDate), "\(alert.managerIdentifier)/\(alert.alertIdentifier)"]
            let content = [alert.contentTitle, alert.contentBody].compactMap { $0 }.joined(separator: ": ")
            if !content.isEmpty {
                parts.append(content.replacingOccurrences(of: "\n", with: " "))
            }
            parts.append(alert.acknowledgedDate.map { "acknowledged \(formatter.string(from: $0))" } ?? "not acknowledged")
            if let error = alert.errorMessage {
                parts.append("error: \(error)")
            }
            return parts.joined(separator: " · ")
        }
        if newestFirst.count > Self.alertLimit {
            lines.append("\(newestFirst.count - Self.alertLimit) older alerts left out")
        }
        return lines
    }

    private static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (simulator)"
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static var freeStorage: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        else { return "unknown" }
        return ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
    }
}

extension LogFileHeader {
    // One `group.key: value` line per encoded setting
    static func settingsLines(_ settings: TrioSettings, _ preferences: Preferences, _ pumpSettings: PumpSettings) -> [String] {
        let encoder = JSONCoding.encoder
        let groups: [(String, [String: Any]?)] = [
            ("settings", encode(settings, encoder)),
            ("preferences", encode(preferences, encoder)),
            ("pumpSettings", encode(pumpSettings, encoder))
        ]
        var lines: [String] = []
        for case let (group, values?) in groups {
            lines += values.keys.sorted().map { "\(group).\($0): \(describe(values[$0]))" }
        }
        return lines
    }

    private static func encode<T: Encodable>(_ value: T, _ encoder: JSONEncoder) -> [String: Any]? {
        guard let data = try? encoder.encode(value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
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
