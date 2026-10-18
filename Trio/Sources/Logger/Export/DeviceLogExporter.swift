import Foundation
import LoopKit
import Swinject

final class DeviceLogExporter: DeviceLogExporting, Injectable {
    @Injected() private var deviceLogStore: DeviceLogStore!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var fetchGlucoseManager: FetchGlucoseManager!

    static let kitFolders = ["danakit", "medtrumkit", "eversense", "accuchek", "libreloop"]
    private static let sliceDuration: TimeInterval = 6 * 60 * 60

    private struct ManagerSnapshot {
        let identifier: String
        let title: String
        let description: String
    }

    private let documentsDirectory: URL
    private var managerProvider: (() -> [DeviceManager])?

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(resolver: Resolver) {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        injectServices(resolver)
    }

    init(store: DeviceLogStore, documentsDirectory: URL, managers: @escaping () -> [DeviceManager]) {
        self.documentsDirectory = documentsDirectory
        managerProvider = managers
        deviceLogStore = store
    }

    func export(_ request: DeviceLogExportRequest, into directory: URL) async throws {
        try await exportDeviceLogs(request, into: directory)
        if request.includeOSLog {
            let since = max(request.window.start, OSLogCapture.processStartDate ?? request.window.start)
            OSLogCapture.write(subsystems: KnownLogSubsystems.all, since: since, into: directory)
        }
        if request.includeKitFiles {
            copyKitFiles(into: directory)
        }
    }

    @MainActor private func liveManagers() -> [ManagerSnapshot] {
        let managers: [DeviceManager]
        if let managerProvider {
            managers = managerProvider()
        } else {
            let candidates: [DeviceManager?] = [deviceDataManager?.pumpManager, fetchGlucoseManager?.cgmManager]
            managers = candidates.compactMap { $0 }
        }
        return managers.map {
            ManagerSnapshot(identifier: $0.pluginIdentifier, title: $0.localizedTitle, description: String(reflecting: $0))
        }
    }

    private func exportDeviceLogs(_ request: DeviceLogExportRequest, into directory: URL) async throws {
        let snapshots = await liveManagers().filter {
            request.managerIdentifier == nil || $0.identifier == request.managerIdentifier
        }
        var handles: [String: FileHandle] = [:]
        defer { handles.values.forEach { try? $0.close() } }

        func handle(for identifier: String) throws -> FileHandle {
            if let handle = handles[identifier] { return handle }
            let header = snapshots.first { $0.identifier == identifier }
                .map { "# \($0.title) (\(identifier))\n\n```\n\($0.description)\n```\n\n" }
                ?? "# \(identifier)\n\n"
            let url = directory.appendingPathComponent("DeviceLog-\(identifier).txt")
            guard FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8)) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            handles[identifier] = handle
            return handle
        }

        for snapshot in snapshots {
            _ = try handle(for: snapshot.identifier)
        }
        if let identifier = request.managerIdentifier {
            _ = try handle(for: identifier)
        }

        guard let deviceLogStore else { return }
        var sliceStart = request.window.start
        while sliceStart < request.window.end {
            let sliceEnd = min(sliceStart.addingTimeInterval(Self.sliceDuration), request.window.end)
            let entries = await deviceLogStore.entries(
                in: DateInterval(start: sliceStart, end: sliceEnd),
                managerIdentifier: request.managerIdentifier
            )
            for entry in entries {
                try handle(for: entry.managerIdentifier).write(contentsOf: Data(line(for: entry).utf8))
            }
            sliceStart = sliceEnd
        }
    }

    private func line(for entry: StoredDeviceLogEntry) -> String {
        let timestamp = dateFormatter.string(from: entry.timestamp)
        let device = entry.deviceIdentifier ?? "-"
        return "* \(timestamp) \(entry.managerIdentifier) \(device) \(entry.type.rawValue) \(entry.message)\n"
    }

    private func copyKitFiles(into directory: URL) {
        let fileManager = FileManager.default
        for folder in Self.kitFolders {
            let source = documentsDirectory.appendingPathComponent(folder, isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else { continue }
            for file in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                do {
                    try fileManager.copyItem(
                        at: file,
                        to: directory.appendingPathComponent("Kit-\(folder)-\(file.lastPathComponent)")
                    )
                } catch {
                    warning(.deviceManager, "Could not copy kit log \(file.lastPathComponent): \(error)")
                }
            }
        }
    }
}
