import Darwin
import Foundation
import OSLog

enum OSLogCapture {
    static let processStartDate: Date? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }()

    // Kit subsystems per pluginIdentifier; Trio's own and LoopKit's mirror duplicate lines already in the file
    static let subsystems: [String: [String]] = [
        "Omni": ["com.loopkit.OmnipodKit", "OmnipodKitPlugin", "com.ps2.rileylink"],
        "Minimed500": ["com.loopkit.MinimedKit", "com.randallknutson.OmniBLE", "com.ps2.rileylink"],
        "Dana": ["com.randallknutson.DanaKit"],
        "Medtrum": ["org.nightscout.MedtrumKit"],
        "EversenseKit": ["org.nightscout.EversenseKit"],
        "AccuChek": ["com.bastiaanv.AccuChekKit"],
        "DexG5Transmitter": ["com.loopkit.CGMBLEKit"],
        "DexG6Transmitter": ["com.loopkit.CGMBLEKit"],
        "G7CGMManager": ["org.loopkit.G7SensorKit", "org.loopkit.G7SensorKitUI", "org.loopkit.G7SensorPlugin"],
        "LibreTransmitterManagerV3": ["com.loopkit.LibreTransmitter", "com.loopkit.libre"],
        "LibreLoopCGMManager": ["org.loopkit.LibreLoop"],
        "SyaiCGMManager": ["org.loopkit.SyaiKit"],
        "DexShareClient": ["com.loopkit.ShareClient"]
    ]

    static func lines(from store: OSLogStore, sources: [String: String], in window: DateInterval) -> [LogLine] {
        guard !sources.isEmpty, window.end >= processStartDate ?? .distantPast else { return [] }
        do {
            let entries = try store.getEntries(
                at: store.position(date: window.start),
                matching: NSPredicate(format: "subsystem IN %@", Array(sources.keys))
            )
            var lines: [LogLine] = []
            for case let entry as OSLogEntryLog in entries {
                if entry.date > window.end { break }
                guard let source = sources[entry.subsystem] else { continue }
                lines.append(LogLine(
                    date: entry.date,
                    source: source,
                    text: "[trace] [\(entry.category)] \(entry.composedMessage)"
                ))
            }
            return lines
        } catch {
            warning(.lifecycle, "Reading Bluetooth traces failed", error: error)
            return []
        }
    }
}
