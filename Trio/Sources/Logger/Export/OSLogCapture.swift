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

    static func write(subsystems: [String], since: Date, into directory: URL) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var handles: [String: FileHandle] = [:]
        var written: [URL] = []

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(
                at: store.position(date: since),
                matching: NSPredicate(format: "subsystem IN %@", subsystems)
            )
            for case let entry as OSLogEntryLog in entries {
                let handle: FileHandle
                if let existing = handles[entry.subsystem] {
                    handle = existing
                } else {
                    let url = directory.appendingPathComponent("OSLog-\(entry.subsystem).txt")
                    guard FileManager.default.createFile(atPath: url.path, contents: Data("# Current app session only\n".utf8))
                    else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
                    written.append(url)
                    handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    handles[entry.subsystem] = handle
                }
                let line =
                    "\(formatter.string(from: entry.date)) \(label(for: entry.level)) [\(entry.category)] \(entry.composedMessage)\n"
                try handle.write(contentsOf: Data(line.utf8))
            }
            handles.values.forEach { try? $0.close() }
        } catch {
            handles.values.forEach { try? $0.close() }
            written.forEach { try? FileManager.default.removeItem(at: $0) }
            warning(.service, "Could not capture os_log entries: \(error)")
        }
    }

    private static func label(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        default: return "default"
        }
    }
}
