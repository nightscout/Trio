import CoreData
import Foundation

extension Stat.StateModel {
    /// Data required to render the "Glucose Distribution" PDF export, resolved for a specific
    /// time interval independently of whatever range is currently selected on screen.
    struct GlucoseDistributionExportData {
        let glucose: [GlucoseStored]
        let rangeStats: [GlucoseRangeStats]
    }

    /// Fetches and computes glucose distribution data for the PDF export, without mutating any
    /// of the published state backing the on-screen chart.
    func prepareGlucoseDistributionExportData(for interval: StatsTimeIntervalWithToday) async -> GlucoseDistributionExportData {
        let ids = await fetchGlucose(for: interval)
        let glucose = await resolveGlucose(ids: ids)
        let rangeStats = await Self.computeGlucoseRangeStats(from: ids, timeInRangeType: timeInRangeType)

        return GlucoseDistributionExportData(glucose: glucose, rangeStats: rangeStats)
    }

    @MainActor private func resolveGlucose(ids: [NSManagedObjectID]) -> [GlucoseStored] {
        do {
            return try ids.compactMap { try viewContext.existingObject(with: $0) as? GlucoseStored }
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#function) error while resolving glucose for export: \(error)")
            return []
        }
    }
}
