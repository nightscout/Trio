import Foundation

/// A named, reusable combination of report chart types and a date range, so a user can rebuild
/// the same multi-page PDF report (e.g. for a recurring clinician visit) without re-picking every
/// chart type each time. Persisted as JSON via `FileStorage`, the same lightweight mechanism
/// already used by several Settings modules — no Core Data entity needed for a small, list-only
/// (no editing) preset feature like this one.
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

    /// Loads all saved report presets, most recently created first.
    func loadReportPresets() -> [ReportPreset] {
        (storage.retrieve(Self.reportPresetsFile, as: [ReportPreset].self) ?? [])
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Saves a new report preset, or overwrites an existing one with the same id.
    func saveReportPreset(_ preset: ReportPreset) {
        var presets = storage.retrieve(Self.reportPresetsFile, as: [ReportPreset].self) ?? []
        presets.removeAll { $0.id == preset.id }
        presets.append(preset)
        storage.save(presets, as: Self.reportPresetsFile)
    }

    /// Deletes a saved report preset.
    func deleteReportPreset(_ preset: ReportPreset) {
        var presets = storage.retrieve(Self.reportPresetsFile, as: [ReportPreset].self) ?? []
        presets.removeAll { $0.id == preset.id }
        storage.save(presets, as: Self.reportPresetsFile)
    }
}
