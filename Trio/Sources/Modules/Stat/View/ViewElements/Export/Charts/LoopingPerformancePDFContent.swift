import SwiftUI

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
