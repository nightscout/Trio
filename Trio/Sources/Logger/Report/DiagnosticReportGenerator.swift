import Foundation
import os
import Swinject

final class DiagnosticReportGenerator: Injectable {
    @Injected() private var deviceLogStore: DeviceLogStore!
    @Injected() private var deviceLogExporter: DeviceLogExporting!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var fetchGlucoseManager: FetchGlucoseManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var keychain: Keychain!
    @Injected() private var reachabilityManager: ReachabilityManager!

    private struct RenderedSection {
        let title: String
        let order: Int
        let body: String
        let directory: URL?
    }

    private static let deviceLogSlice: TimeInterval = 6 * 60 * 60

    private let sectionTimeout: TimeInterval
    private let sectionsOverride: ((Bool) -> [DiagnosticReportSection])?
    private let exactValuesOverride: ((DateInterval) async -> [Redactor.ExactValue])?

    init(resolver: Resolver) {
        sectionTimeout = 10
        sectionsOverride = nil
        exactValuesOverride = nil
        injectServices(resolver)
    }

    init(
        sectionTimeout: TimeInterval,
        sections: @escaping (Bool) -> [DiagnosticReportSection],
        exactValues: @escaping (DateInterval) async -> [Redactor.ExactValue] = { _ in [] }
    ) {
        self.sectionTimeout = sectionTimeout
        sectionsOverride = sections
        exactValuesOverride = exactValues
    }

    @discardableResult func generate(window: DateInterval, includeDebug: Bool, into directory: URL) async throws -> String {
        let fileManager = FileManager.default
        // Sections write into staging so a timed-out section can never add unredacted files to the report
        let staging = fileManager.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let sections = sectionsOverride?(includeDebug) ?? defaultSections(includeDebug: includeDebug)
        let timeout = sectionTimeout
        let rendered = await withTaskGroup(of: RenderedSection.self) { group in
            for (index, section) in sections.enumerated() {
                let sectionDirectory = staging.appendingPathComponent("\(index)", isDirectory: true)
                group.addTask {
                    try? FileManager.default.createDirectory(at: sectionDirectory, withIntermediateDirectories: true)
                    let body = await Self.render(section, window: window, into: sectionDirectory, timeout: timeout)
                    return RenderedSection(
                        title: section.title,
                        order: section.order,
                        body: body ?? "_timed out_",
                        directory: body == nil ? nil : sectionDirectory
                    )
                }
            }
            var results: [RenderedSection] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.order < $1.order }
        }

        for section in rendered {
            if let sectionDirectory = section.directory {
                moveContents(of: sectionDirectory, to: directory, prefix: "\(section.order)-")
            }
        }

        let markdown = Self.markdown(for: rendered, window: window, generatedAt: Date())
        let reportURL = directory.appendingPathComponent("Trio Report \(ReportFormatting.fileStamp(Date())).md")
        try markdown.write(to: reportURL, atomically: true, encoding: .utf8)

        let exactValues: [Redactor.ExactValue]
        if let exactValuesOverride {
            exactValues = await exactValuesOverride(window)
        } else {
            exactValues = await defaultExactValues(in: window)
        }
        try Redactor(exactValues: exactValues).redactFiles(in: directory)
        return try String(contentsOf: reportURL, encoding: .utf8)
    }

    func archive(window: DateInterval, includeDebug: Bool) async throws -> URL {
        try await LogShareAction.archive(named: "Trio-Report-\(ReportFormatting.archiveStamp(Date()))") { directory in
            _ = try await self.generate(window: window, includeDebug: includeDebug, into: directory)
        }
    }

    func markdown(window: DateInterval, includeDebug: Bool) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await generate(window: window, includeDebug: includeDebug, into: directory)
    }

    private static func render(
        _ section: DiagnosticReportSection,
        window: DateInterval,
        into directory: URL,
        timeout: TimeInterval
    ) async -> String? {
        let finished = OSAllocatedUnfairLock(initialState: false)
        let claim = { finished.withLock { done in
            defer { done = true }
            return !done
        } }
        return await withCheckedContinuation { continuation in
            let work = Task {
                let body = await section.render(window: window, into: directory)
                if claim() { continuation.resume(returning: body) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                if claim() {
                    work.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func markdown(for sections: [RenderedSection], window: DateInterval, generatedAt: Date) -> String {
        var lines = [
            "# Trio Report",
            "",
            "Generated at: \(ReportFormatting.timestamp(generatedAt))",
            "Window: \(ReportFormatting.timestamp(window.start)) – \(ReportFormatting.timestamp(window.end))"
        ]
        for section in sections {
            lines += ["", "## \(section.title)", "", section.body.trimmingCharacters(in: .newlines)]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func moveContents(of source: URL, to destination: URL, prefix: String) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for file in files {
            var target = destination.appendingPathComponent(file.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                target = destination.appendingPathComponent(prefix + file.lastPathComponent)
            }
            do {
                try fileManager.moveItem(at: file, to: target)
            } catch {
                warning(.service, "Could not add \(file.lastPathComponent) to the report: \(error)")
            }
        }
    }

    private func defaultSections(includeDebug: Bool) -> [DiagnosticReportSection] {
        let deviceDataManager = self.deviceDataManager
        let fetchGlucoseManager = self.fetchGlucoseManager
        return [
            BuildSection(),
            DeviceInfoSection(),
            SettingsSection(settingsManager: settingsManager),
            DeviceManagersSection(
                pumpManager: { deviceDataManager?.pumpManager },
                cgmManager: { fetchGlucoseManager?.cgmManager }
            ),
            AlertsSection(),
            DeterminationsSection(),
            LoopTimingSection(),
            NightscoutSection(settingsManager: settingsManager, keychain: keychain, reachabilityManager: reachabilityManager),
            WatchSection(),
            AppLogSection(includeDebug: includeDebug),
            DeviceLogSection(exporter: deviceLogExporter)
        ]
    }

    private func defaultExactValues(in window: DateInterval) async -> [Redactor.ExactValue] {
        var values: [Redactor.ExactValue] = []
        let url: String? = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.urlKey)
        if let url, !url.isEmpty {
            values.append(Redactor.ExactValue(value: url, kind: .url))
            if url.hasSuffix("/") {
                values.append(Redactor.ExactValue(value: String(url.dropLast()), kind: .url))
            }
            if let host = URL(string: url)?.host {
                values.append(Redactor.ExactValue(value: host, kind: .host))
            }
        }
        let secret: String? = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        if let secret, !secret.isEmpty {
            values.append(Redactor.ExactValue(value: secret, kind: .secret))
        }
        for identifier in await deviceIdentifiers(in: window).sorted() {
            values.append(Redactor.ExactValue(value: identifier, kind: .device))
        }
        return values
    }

    private func deviceIdentifiers(in window: DateInterval) async -> Set<String> {
        guard let deviceLogStore else { return [] }
        var identifiers = Set<String>()
        var sliceStart = window.start
        while sliceStart < window.end {
            let sliceEnd = min(sliceStart.addingTimeInterval(Self.deviceLogSlice), window.end)
            for entry in await deviceLogStore.entries(in: DateInterval(start: sliceStart, end: sliceEnd)) {
                if let identifier = entry.deviceIdentifier, !identifier.isEmpty {
                    identifiers.insert(identifier)
                }
            }
            sliceStart = sliceEnd
        }
        return identifiers
    }
}

enum ReportFormatting {
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func timestamp(_ date: Date?) -> String {
        date.map { timestampFormatter.string(from: $0) } ?? "-"
    }

    static func number(_ value: Decimal?) -> String {
        value.flatMap { numberFormatter.string(from: $0 as NSDecimalNumber) } ?? "-"
    }

    static func number(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func fenced(_ text: String) -> String {
        let fence = text.contains("```") ? "~~~~" : "```"
        return "\(fence)\n\(text.trimmingCharacters(in: .newlines))\n\(fence)"
    }

    static func fileStamp(_ date: Date) -> String {
        stamp(date, format: "yyyy-MM-dd HH-mm")
    }

    static func archiveStamp(_ date: Date) -> String {
        stamp(date, format: "yyyyMMdd-HHmm")
    }

    private static func stamp(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
