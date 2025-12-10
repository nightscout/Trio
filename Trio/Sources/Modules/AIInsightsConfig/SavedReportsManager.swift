import Foundation
import PDFKit
import UIKit

/// Manages saving, loading, and deleting AI analysis reports as PDF files
final class SavedReportsManager {
    // MARK: - Types

    enum ReportType: String, CaseIterable {
        case quickAnalysis = "QuickAnalysis"
        case weeklyReport = "WeeklyReport"
        case doctorReport = "DoctorReport"

        var displayName: String {
            switch self {
            case .quickAnalysis: return "Quick Analysis"
            case .weeklyReport: return "Weekly Report"
            case .doctorReport: return "Doctor Report"
            }
        }

        var icon: String {
            switch self {
            case .quickAnalysis: return "bolt.fill"
            case .weeklyReport: return "doc.text.fill"
            case .doctorReport: return "stethoscope"
            }
        }

        var color: String {
            switch self {
            case .quickAnalysis: return "yellow"
            case .weeklyReport: return "green"
            case .doctorReport: return "purple"
            }
        }
    }

    struct SavedReport: Identifiable, Codable {
        let id: UUID
        let type: String
        let filename: String
        let dateGenerated: Date
        let timePeriod: String

        var reportType: ReportType? {
            ReportType(rawValue: type)
        }
    }

    // MARK: - Constants

    private static let maxReportsPerType = 10
    private static let reportsDirectoryName = "AIReports"
    private static let manifestFilename = "reports_manifest.json"

    // MARK: - Singleton

    static let shared = SavedReportsManager()

    private init() {
        createDirectoriesIfNeeded()
    }

    // MARK: - Directory Management

    private var reportsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(Self.reportsDirectoryName)
    }

    private func directoryForType(_ type: ReportType) -> URL {
        reportsDirectory.appendingPathComponent(type.rawValue)
    }

    private func createDirectoriesIfNeeded() {
        let fileManager = FileManager.default

        // Create main reports directory
        if !fileManager.fileExists(atPath: reportsDirectory.path) {
            try? fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        }

        // Create subdirectories for each report type
        for type in ReportType.allCases {
            let typeDir = directoryForType(type)
            if !fileManager.fileExists(atPath: typeDir.path) {
                try? fileManager.createDirectory(at: typeDir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Manifest Management

    private var manifestURL: URL {
        reportsDirectory.appendingPathComponent(Self.manifestFilename)
    }

    private func loadManifest() -> [SavedReport] {
        guard let data = try? Data(contentsOf: manifestURL),
              let reports = try? JSONDecoder().decode([SavedReport].self, from: data)
        else {
            return []
        }
        return reports
    }

    private func saveManifest(_ reports: [SavedReport]) {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        try? data.write(to: manifestURL)
    }

    // MARK: - Public API

    /// Save a report as PDF and return the saved report info
    @discardableResult
    func saveReport(
        type: ReportType,
        content: String,
        timePeriod: String,
        pdfData: Data
    ) -> SavedReport? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let filename = "report_\(timestamp).pdf"
        let fileURL = directoryForType(type).appendingPathComponent(filename)

        // Save PDF file
        do {
            try pdfData.write(to: fileURL)
        } catch {
            print("Failed to save PDF: \(error)")
            return nil
        }

        // Create report entry
        let report = SavedReport(
            id: UUID(),
            type: type.rawValue,
            filename: filename,
            dateGenerated: Date(),
            timePeriod: timePeriod
        )

        // Update manifest
        var reports = loadManifest()
        reports.insert(report, at: 0)

        // Enforce max reports per type
        let reportsOfType = reports.filter { $0.type == type.rawValue }
        if reportsOfType.count > Self.maxReportsPerType {
            let reportsToDelete = reportsOfType.suffix(from: Self.maxReportsPerType)
            for reportToDelete in reportsToDelete {
                deleteReportFile(reportToDelete)
                reports.removeAll { $0.id == reportToDelete.id }
            }
        }

        saveManifest(reports)
        return report
    }

    /// Get all saved reports, optionally filtered by type
    func getSavedReports(type: ReportType? = nil) -> [SavedReport] {
        var reports = loadManifest()

        // Sort by date, newest first
        reports.sort { $0.dateGenerated > $1.dateGenerated }

        if let type = type {
            reports = reports.filter { $0.type == type.rawValue }
        }

        // Verify files still exist
        reports = reports.filter { report in
            guard let reportType = report.reportType else { return false }
            let fileURL = directoryForType(reportType).appendingPathComponent(report.filename)
            return FileManager.default.fileExists(atPath: fileURL.path)
        }

        return reports
    }

    /// Get PDF data for a saved report
    func getPDFData(for report: SavedReport) -> Data? {
        guard let reportType = report.reportType else { return nil }
        let fileURL = directoryForType(reportType).appendingPathComponent(report.filename)
        return try? Data(contentsOf: fileURL)
    }

    /// Get file URL for a saved report
    func getFileURL(for report: SavedReport) -> URL? {
        guard let reportType = report.reportType else { return nil }
        let fileURL = directoryForType(reportType).appendingPathComponent(report.filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    /// Delete a specific report
    func deleteReport(_ report: SavedReport) {
        deleteReportFile(report)

        var reports = loadManifest()
        reports.removeAll { $0.id == report.id }
        saveManifest(reports)
    }

    /// Delete all reports of a specific type
    func deleteAllReports(ofType type: ReportType) {
        var reports = loadManifest()
        let reportsToDelete = reports.filter { $0.type == type.rawValue }

        for report in reportsToDelete {
            deleteReportFile(report)
        }

        reports.removeAll { $0.type == type.rawValue }
        saveManifest(reports)
    }

    /// Delete all saved reports
    func deleteAllReports() {
        let reports = loadManifest()
        for report in reports {
            deleteReportFile(report)
        }
        saveManifest([])
    }

    private func deleteReportFile(_ report: SavedReport) {
        guard let reportType = report.reportType else { return }
        let fileURL = directoryForType(reportType).appendingPathComponent(report.filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Report Count

    func reportCount(for type: ReportType? = nil) -> Int {
        getSavedReports(type: type).count
    }

    func totalReportCount() -> Int {
        loadManifest().count
    }
}

// MARK: - Date Formatting Extension

extension SavedReport {
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateGenerated)
    }

    var relativeDateString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: dateGenerated, relativeTo: Date())
    }
}
