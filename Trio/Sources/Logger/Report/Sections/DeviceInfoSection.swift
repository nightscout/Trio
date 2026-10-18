import Foundation

struct DeviceInfoSection: DiagnosticReportSection {
    let title = "Device"
    let order = 10

    func render(window _: DateInterval, into _: URL) async -> String {
        let processInfo = ProcessInfo.processInfo
        return [
            "- OS: \(processInfo.operatingSystemVersionString)",
            "- Model: \(Self.modelIdentifier)",
            "- Low Power Mode: \(processInfo.isLowPowerModeEnabled ? "on" : "off")",
            "- Thermal state: \(Self.label(for: processInfo.thermalState))",
            "- Free disk: \(Self.freeDisk)",
            "- Time zone: \(TimeZone.current.identifier)"
        ].joined(separator: "\n")
    }

    static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (simulator)"
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static var freeDisk: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        else { return "unknown" }
        return ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
    }

    private static func label(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
