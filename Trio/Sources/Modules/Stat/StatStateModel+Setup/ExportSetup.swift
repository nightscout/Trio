import CoreData
import Foundation
import SwiftUI

extension Stat.StateModel {
    /// Data required to render the "Glucose Distribution" PDF export, resolved for a specific
    /// time interval independently of whatever range is currently selected on screen.
    struct GlucoseDistributionExportData {
        let glucose: [GlucoseStored]
        let rangeStats: [GlucoseRangeStats]
    }

    /// Device/algorithm context shown in the PDF export header, so a report can be understood
    /// on its own without the reader having to cross-reference the app's current settings.
    struct ReportMetadata {
        struct Hardware {
            let cgmName: String
            let pumpName: String
            let iPhoneType: String
        }

        struct Software {
            let trioVersion: String
            let buildDate: String
        }

        struct ImportantSettings {
            let dynamicISFEnabled: Bool
            let smbEnabled: Bool
            let uamEnabled: Bool
            let closedLoopActive: Bool
        }

        let hardware: Hardware
        let software: Software
        let importantSettings: ImportantSettings
    }

    /// Fetches and computes glucose distribution data for the PDF export, without mutating any
    /// of the published state backing the on-screen chart.
    func prepareGlucoseDistributionExportData(for interval: StatsTimeIntervalWithToday) async -> GlucoseDistributionExportData {
        let ids = await fetchGlucose(for: interval)
        let glucose = await resolveGlucose(ids: ids)
        let rangeStats = await Self.computeGlucoseRangeStats(from: ids, timeInRangeType: timeInRangeType)

        return GlucoseDistributionExportData(glucose: glucose, rangeStats: rangeStats)
    }

    /// Data required to render the "Glucose Percentile" (AGP) PDF export.
    struct GlucosePercentileExportData {
        let glucose: [GlucoseStored]
        let hourlyStats: [HourlyStats]
    }

    /// Fetches and computes hourly percentile data for the AGP PDF export, independent of
    /// whatever interval is currently selected for the on-screen AGP chart.
    func preparePercentileExportData(for interval: StatsTimeIntervalWithToday) async -> GlucosePercentileExportData {
        let ids = await fetchGlucose(for: interval)
        let glucose = await resolveGlucose(ids: ids)
        let hourlyStats = await Self.computeHourlyStats(from: ids)

        return GlucosePercentileExportData(glucose: glucose, hourlyStats: hourlyStats)
    }

    /// Data required to render the "Glucose Percentile by Day" PDF export.
    struct GlucosePercentileByDayExportData {
        let dailyStats: [GlucoseDailyPercentileStats]
    }

    /// Fetches and computes per-day percentile data for the requested export range.
    func prepareGlucosePercentileByDayExportData(for interval: StatsTimeInterval) async -> GlucosePercentileByDayExportData {
        let widened = StatsTimeIntervalWithToday(rawValue: interval.rawValue) ?? .month
        let ids = await fetchGlucose(for: widened)
        let dates = Self.dayArray(from: interval.periodStart, to: Date())
        let dailyStats = await calculateDailyPercentileStats(for: dates, glucoseIDs: ids)

        return GlucosePercentileByDayExportData(dailyStats: dailyStats)
    }

    /// Data required to render the "Glucose Distribution by Day" PDF export.
    struct GlucoseDistributionByDayExportData {
        let dailyStats: [GlucoseDailyDistributionStats]
    }

    /// Fetches and computes per-day distribution data for the requested export range.
    func prepareGlucoseDistributionByDayExportData(for interval: StatsTimeInterval) async -> GlucoseDistributionByDayExportData {
        let widened = StatsTimeIntervalWithToday(rawValue: interval.rawValue) ?? .month
        let ids = await fetchGlucose(for: widened)
        let dates = Self.dayArray(from: interval.periodStart, to: Date())
        let dailyStats = await calculateDailyDistributionStats(
            for: dates,
            glucoseIDs: ids,
            highLimit: highLimit,
            timeInRangeType: timeInRangeType
        )

        return GlucoseDistributionByDayExportData(dailyStats: dailyStats)
    }

    /// Data required to render the "Total Daily Dose" PDF export.
    struct TDDExportData {
        let stats: [TDDStats]
    }

    /// Filters the already-loaded TDD stats (hourly covers the last 20 days, daily covers the
    /// last 3 months — both comfortably cover the export's largest selectable range) down to the
    /// requested export interval.
    @MainActor func prepareTDDExportData(for interval: StatsTimeInterval) -> TDDExportData {
        let stats = interval == .day
            ? hourlyTDDStats.filter { $0.date >= interval.periodStart }
            : dailyTDDStats.filter { $0.date >= interval.periodStart }

        return TDDExportData(stats: stats)
    }

    /// Data required to render the "Bolus Distribution" PDF export.
    struct BolusExportData {
        let stats: [BolusStats]
    }

    /// Filters the already-loaded bolus stats (hourly covers the last 20 days, daily covers the
    /// last 3 months) down to the requested export interval.
    @MainActor func prepareBolusExportData(for interval: StatsTimeInterval) -> BolusExportData {
        let stats = interval == .day
            ? hourlyBolusStats.filter { $0.date >= interval.periodStart }
            : dailyBolusStats.filter { $0.date >= interval.periodStart }

        return BolusExportData(stats: stats)
    }

    /// Data required to render the "Total Meals" PDF export.
    struct MealsExportData {
        let stats: [MealStats]
        let useFPUconversion: Bool
    }

    /// Filters the already-loaded meal stats (hourly covers the last 20 days, daily covers the
    /// last 3 months) down to the requested export interval.
    @MainActor func prepareMealsExportData(for interval: StatsTimeInterval) -> MealsExportData {
        let stats = interval == .day
            ? hourlyMealStats.filter { $0.date >= interval.periodStart }
            : dailyMealStats.filter { $0.date >= interval.periodStart }

        return MealsExportData(stats: stats, useFPUconversion: useFPUconversion)
    }

    /// Data required to render the "Looping Performance" PDF export.
    struct LoopingExportData {
        let loopStatRecords: [LoopStatRecord]
        let loopStats: [LoopStatsProcessedData]
    }

    /// Fetches and computes loop performance data for the PDF export, without mutating any of the
    /// published state backing the on-screen chart.
    func prepareLoopingExportData(for interval: StatsTimeIntervalWithToday) async -> LoopingExportData {
        do {
            let (allLoopIds, failedLoopIds) = try await fetchLoopStatRecords(for: interval)
            let loopStatRecords = await resolveLoopStatRecords(ids: allLoopIds)
            let loopStats = try await getLoopStats(allLoopIds: allLoopIds, failedLoopIds: failedLoopIds, interval: interval)

            return LoopingExportData(loopStatRecords: loopStatRecords, loopStats: loopStats)
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#function) error while preparing looping export data: \(error)")
            return LoopingExportData(loopStatRecords: [], loopStats: [])
        }
    }

    /// Generates one `Date` per calendar day, from `start` through `end` (inclusive).
    private static func dayArray(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        let last = calendar.startOfDay(for: end)
        var current = calendar.startOfDay(for: start)
        var dates: [Date] = []

        while current <= last, dates.count <= 100 { // upper bound guards against malformed ranges
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return dates
    }

    @MainActor private func resolveLoopStatRecords(ids: [NSManagedObjectID]) -> [LoopStatRecord] {
        ids.compactMap { id -> LoopStatRecord? in
            do {
                return try viewContext.existingObject(with: id) as? LoopStatRecord
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#function) error while resolving loop stat record for export: \(error)"
                )
                return nil
            }
        }
    }

    /// Resolves the device and algorithm context shown in the PDF export header.
    @MainActor func prepareReportMetadata() -> ReportMetadata {
        let cgmName: String
        switch settingsManager.settings.cgm {
        case .plugin:
            cgmName = fetchGlucoseManager.cgmManager?.localizedTitle ?? settingsManager.settings.cgm.displayName
        default:
            cgmName = settingsManager.settings.cgm.displayName
        }

        let preferences = settingsManager.preferences
        let smbEnabled = preferences.enableSMBAlways
            || preferences.enableSMBWithCOB
            || preferences.enableSMBWithTemptarget
            || preferences.enableSMBAfterCarbs

        return ReportMetadata(
            hardware: ReportMetadata.Hardware(
                cgmName: cgmName,
                pumpName: apsManager.pumpName.value,
                iPhoneType: UIDevice.current.getDeviceId
            ),
            software: ReportMetadata.Software(
                trioVersion: Bundle.main.releaseVersionNumber ?? String(localized: "Unknown"),
                buildDate: BuildDetails.shared.buildDateString ?? String(localized: "Unknown")
            ),
            importantSettings: ReportMetadata.ImportantSettings(
                dynamicISFEnabled: preferences.useNewFormula,
                smbEnabled: smbEnabled,
                uamEnabled: preferences.enableUAM,
                closedLoopActive: settingsManager.settings.closedLoop
            )
        )
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
