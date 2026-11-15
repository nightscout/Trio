import CoreData
import Foundation
import SwiftUI

extension Stat.StateModel {
    /// Glucose Distribution PDF data for an interval, independent of the on-screen selection.
    struct GlucoseDistributionExportData {
        let glucose: [GlucoseStored]
        let rangeStats: [GlucoseRangeStats]
    }

    /// Device and algorithm details for the PDF header.
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

    /// Glucose distribution data for the export. Leaves the on-screen chart state untouched.
    func prepareGlucoseDistributionExportData(for interval: StatsTimeIntervalWithToday) async -> GlucoseDistributionExportData {
        let ids = await fetchGlucose(for: interval)
        let glucose = await resolveGlucose(ids: ids)
        let rangeStats = await Self.computeGlucoseRangeStats(from: ids, timeInRangeType: timeInRangeType)

        return GlucoseDistributionExportData(glucose: glucose, rangeStats: rangeStats)
    }

    /// Glucose Percentile (AGP) PDF data.
    struct GlucosePercentileExportData {
        let glucose: [GlucoseStored]
        let hourlyStats: [HourlyStats]
    }

    /// Hourly percentile data for the export, independent of the on-screen interval.
    func preparePercentileExportData(for interval: StatsTimeIntervalWithToday) async -> GlucosePercentileExportData {
        let ids = await fetchGlucose(for: interval)
        let glucose = await resolveGlucose(ids: ids)
        let hourlyStats = await Self.computeHourlyStats(from: ids)

        return GlucosePercentileExportData(glucose: glucose, hourlyStats: hourlyStats)
    }

    /// Glucose Percentile by Day PDF data.
    struct GlucosePercentileByDayExportData {
        let dailyStats: [GlucoseDailyPercentileStats]
    }

    /// Per-day percentile data for the export range.
    func prepareGlucosePercentileByDayExportData(for interval: StatsTimeInterval) async -> GlucosePercentileByDayExportData {
        let widened = StatsTimeIntervalWithToday(rawValue: interval.rawValue) ?? .month
        let ids = await fetchGlucose(for: widened)
        let dates = Self.dayArray(from: interval.periodStart, to: Date())
        let dailyStats = await calculateDailyPercentileStats(for: dates, glucoseIDs: ids)

        return GlucosePercentileByDayExportData(dailyStats: dailyStats)
    }

    /// Glucose Distribution by Day PDF data.
    struct GlucoseDistributionByDayExportData {
        let dailyStats: [GlucoseDailyDistributionStats]
    }

    /// Per-day distribution data for the export range.
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

    /// Glycemia Risk Index PDF data.
    struct GRIExportData {
        let result: GRICalculator.Result?
    }

    /// GRI for the export range, using the same calculator as the on-screen chart.
    func prepareGRIExportData(for interval: StatsTimeIntervalWithToday) async -> GRIExportData {
        let ids = await fetchGlucose(for: interval)
        let glucose = await resolveGlucose(ids: ids)
        let result = GRICalculator.calculate(glucoseValues: glucose.map { Int($0.glucose) })

        return GRIExportData(result: result)
    }

    /// Total Daily Dose PDF data.
    struct TDDExportData {
        let stats: [TDDStats]
    }

    /// Filters the loaded TDD stats to the export interval. Hourly stats cover 20 days and
    /// daily stats 3 months, which covers every export range.
    @MainActor func prepareTDDExportData(for interval: StatsTimeInterval) -> TDDExportData {
        let stats = interval == .day
            ? hourlyTDDStats.filter { $0.date >= interval.periodStart }
            : dailyTDDStats.filter { $0.date >= interval.periodStart }

        return TDDExportData(stats: stats)
    }

    /// Bolus Distribution PDF data.
    struct BolusExportData {
        let stats: [BolusStats]
    }

    /// Filters the loaded bolus stats to the export interval.
    @MainActor func prepareBolusExportData(for interval: StatsTimeInterval) -> BolusExportData {
        let stats = interval == .day
            ? hourlyBolusStats.filter { $0.date >= interval.periodStart }
            : dailyBolusStats.filter { $0.date >= interval.periodStart }

        return BolusExportData(stats: stats)
    }

    /// Total Meals PDF data.
    struct MealsExportData {
        let stats: [MealStats]
        let useFPUconversion: Bool
    }

    /// Filters the loaded meal stats to the export interval.
    @MainActor func prepareMealsExportData(for interval: StatsTimeInterval) -> MealsExportData {
        let stats = interval == .day
            ? hourlyMealStats.filter { $0.date >= interval.periodStart }
            : dailyMealStats.filter { $0.date >= interval.periodStart }

        return MealsExportData(stats: stats, useFPUconversion: useFPUconversion)
    }

    /// Looping Performance PDF data.
    struct LoopingExportData {
        let loopStatRecords: [LoopStatRecord]
        let loopStats: [LoopStatsProcessedData]
    }

    /// Loop performance data for the export. Leaves the on-screen chart state untouched.
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

    /// One `Date` per calendar day from `start` through `end`, inclusive.
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

    /// Device and algorithm details for the PDF header.
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
                iPhoneType: UIDevice.current.marketingName
            ),
            software: ReportMetadata.Software(
                trioVersion: Bundle.main.releaseVersionNumber ?? String(localized: "Unknown"),
                buildDate: BuildDetails.shared.buildDateString ?? String(localized: "Unknown")
            ),
            importantSettings: ReportMetadata.ImportantSettings(
                dynamicISFEnabled: preferences.useNewFormula,
                smbEnabled: smbEnabled,
                uamEnabled: preferences.enableUAM,
                closedLoopActive: settingsManager.settings.dosingMode == .closed
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
