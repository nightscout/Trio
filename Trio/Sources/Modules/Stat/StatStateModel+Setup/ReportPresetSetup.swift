import Foundation

/// A saved set of report charts and date range, stored as JSON via `FileStorage`.
struct ReportPreset: JSON, Identifiable, Equatable {
    let id: UUID
    var name: String
    var range: Stat.StateModel.StatsTimeInterval
    var chartTypes: [ReportChartType]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        range: Stat.StateModel.StatsTimeInterval,
        chartTypes: [ReportChartType],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.range = range
        self.chartTypes = chartTypes
        self.createdAt = createdAt
    }
}

extension Stat.StateModel {
    private static let reportPresetsFile = "settings/stat_report_presets.json"

    /// Saved presets, newest first.
    func loadReportPresets() -> [ReportPreset] {
        (storage.retrieve(Self.reportPresetsFile, as: [ReportPreset].self) ?? [])
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Saves a preset, replacing any with the same id.
    func saveReportPreset(_ preset: ReportPreset) {
        var presets = storage.retrieve(Self.reportPresetsFile, as: [ReportPreset].self) ?? []
        presets.removeAll { $0.id == preset.id }
        presets.append(preset)
        storage.save(presets, as: Self.reportPresetsFile)
    }

    func deleteReportPreset(_ preset: ReportPreset) {
        var presets = storage.retrieve(Self.reportPresetsFile, as: [ReportPreset].self) ?? []
        presets.removeAll { $0.id == preset.id }
        storage.save(presets, as: Self.reportPresetsFile)
    }
}

/// Patient name for PDF headers, remembered to prefill the export prompt.
struct ReportPatientInfo: JSON, Equatable {
    var name: String
}

extension Stat.StateModel {
    private static let reportPatientFile = "settings/stat_report_patient.json"

    /// The last patient name used, if any.
    func loadReportPatientName() -> String? {
        storage.retrieve(Self.reportPatientFile, as: ReportPatientInfo.self)?.name
    }

    func saveReportPatientName(_ name: String) {
        storage.save(ReportPatientInfo(name: name), as: Self.reportPatientFile)
    }
}
