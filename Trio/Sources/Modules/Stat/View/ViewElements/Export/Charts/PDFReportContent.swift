import SwiftUI

/// PDF page content for the "Glucose Distribution" export.
/// Reuses the same chart/stat components shown in the on-screen Statistics sheet.
struct GlucoseDistributionPDFContent: View {
    let glucose: [GlucoseStored]
    let glucoseRangeStats: [GlucoseRangeStats]
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit
    let timeInRangeType: TimeInRangeType

    var body: some View {
        GlucoseDistributionChart(
            glucose: glucose,
            highLimit: highLimit,
            lowLimit: lowLimit,
            units: units,
            glucoseRangeStats: glucoseRangeStats,
            timeInRangeType: timeInRangeType
        )

        Divider()

        VStack(spacing: 16) {
            GlucoseSectorChart(
                highLimit: highLimit,
                units: units,
                glucose: glucose,
                timeInRangeType: timeInRangeType,
                showChart: true
            )

            Divider()

            GlucoseMetricsView(
                units: units,
                eA1cDisplayUnit: eA1cDisplayUnit,
                glucose: glucose
            )
        }
    }
}

/// PDF page content for the "Glucose Percentile" (AGP) export.
/// Reuses the same AGP chart shown in the on-screen Statistics sheet.
struct GlucosePercentilePDFContent: View {
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let timeInRangeType: TimeInRangeType
    let units: GlucoseUnits
    let hourlyStats: [HourlyStats]

    var body: some View {
        GlucosePercentileChart(
            glucose: glucose,
            highLimit: highLimit,
            timeInRangeType: timeInRangeType,
            units: units,
            hourlyStats: hourlyStats,
            isToday: false
        )
    }
}

/// PDF page content for the "Looping Performance" export.
/// Reuses the same static bar chart and stats row shown in the on-screen Statistics sheet.
struct LoopingPerformancePDFContent: View {
    let loopStatRecords: [LoopStatRecord]
    let selectedInterval: Stat.StateModel.StatsTimeIntervalWithToday
    let loopStats: [LoopStatsProcessedData]

    var body: some View {
        LoopBarChartView(
            loopStatRecords: loopStatRecords,
            selectedInterval: selectedInterval,
            statsData: loopStats
        )

        Divider()

        LoopStatsView(statsData: loopStats)
    }
}
