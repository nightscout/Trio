import Foundation

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
