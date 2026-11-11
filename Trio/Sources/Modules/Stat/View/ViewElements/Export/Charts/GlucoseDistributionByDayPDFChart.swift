import Charts
import SwiftUI

/// A static, full-range rendering of the per-day glucose distribution chart for PDF export.
/// Mirrors `GlucoseDailyDistributionChart`'s marks/colors/legend exactly, but shows every day in
/// the export range at once instead of a scrollable window, and drops the interactive
/// day-selection/sector-chart/metrics overlay (not meaningful in a static, non-interactive PDF).
struct GlucoseDistributionByDayPDFChart: View {
    let dailyStats: [GlucoseDailyDistributionStats]
    let highLimit: Decimal
    let units: GlucoseUnits
    let timeInRangeType: TimeInRangeType
    let selectedInterval: Stat.StateModel.StatsTimeInterval

    var body: some View {
        Chart {
            ForEach(dailyStats) { day in
                barMark(x: day, y: day.veryLowPct, rangeName: "veryLow")
                barMark(x: day, y: day.lowPct, rangeName: "low")
                barMark(x: day, y: day.inSmallRangePct, rangeName: "inSmallRange")
                barMark(x: day, y: day.inRangePct - day.inSmallRangePct, rangeName: "inRange")
                barMark(x: day, y: day.highPct, rangeName: "high")
                barMark(x: day, y: day.veryHighPct, rangeName: "veryHigh")
            }
        }
        .chartForegroundStyleScale([
            legend("veryLow"): .purple,
            legend("low"): .red,
            legend("inSmallRange"): .green,
            legend("inRange"): .darkGreen,
            legend("high"): .loopYellow,
            legend("veryHigh"): .orange
        ])
        .chartYScale(domain: 0 ... 100)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    StatChartUtils.axisMarkContent(for: date, selectedInterval: selectedInterval, font: .caption2)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [4, 25, 50, 75, 100]) { value in
                if let percentage = value.as(Double.self) {
                    AxisValueLabel {
                        Text((percentage / 100).formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption2)
                    }
                    AxisGridLine()
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 8)
        .frame(height: 260)
    }

    /// Formats a short string with the glucose values of the requested range.
    private func legend(_ rangeName: String) -> String {
        StatChartUtils.glucoseDistributionRangeLabel(
            rangeName,
            highLimit: highLimit,
            units: units,
            timeInRangeType: timeInRangeType
        )
    }

    private func barMark(x: GlucoseDailyDistributionStats, y: Double, rangeName: String) -> some ChartContent {
        BarMark(
            x: .value("Date", x.date, unit: .day),
            y: .value("Percentage", y)
        )
        .foregroundStyle(by: .value("Range", legend(rangeName)))
    }
}
