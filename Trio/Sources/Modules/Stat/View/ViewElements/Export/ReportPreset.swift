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
