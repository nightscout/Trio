import Charts
import SwiftUI

/// A static, full-range rendering of the per-day glucose percentile ("boxplot") chart for PDF
/// export. Mirrors `GlucoseDailyPercentileChart`'s marks/colors/legend exactly, but shows every
/// day in the export range at once instead of a scrollable window, and drops the interactive
/// day-selection/percentile-detail overlay (not meaningful in a static, non-interactive PDF).
struct GlucosePercentileByDayPDFChart: View {
    let dailyStats: [GlucoseDailyPercentileStats]
    let highLimit: Decimal
    let units: GlucoseUnits
    let timeInRangeType: TimeInRangeType
    let selectedInterval: Stat.StateModel.StatsTimeInterval

    var body: some View {
        boxplotChart
            .frame(height: 260)
    }

    private var boxplotChart: some View {
        Chart {
            ForEach(dailyStats) { day in
                if day.maximum > 0 {
                    spacerBarMark(for: day)
                    percentileBarMark(
                        for: day,
                        startValue: day.minimum.asUnit(units),
                        endValue: day.percentile10.asUnit(units),
                        rangeName: "0-100%"
                    )
                    percentileBarMark(
                        for: day,
                        startValue: day.percentile10.asUnit(units),
                        endValue: day.percentile25.asUnit(units),
                        rangeName: "10-90%"
                    )
                    percentileBarMark(
                        for: day,
                        startValue: day.percentile25.asUnit(units),
                        endValue: day.percentile75.asUnit(units),
                        rangeName: "25-75%"
                    )
                    percentileBarMark(
                        for: day,
                        startValue: day.percentile75.asUnit(units),
                        endValue: day.percentile90.asUnit(units),
                        rangeName: "10-90%"
                    )
                    percentileBarMark(
                        for: day,
                        startValue: day.percentile90.asUnit(units),
                        endValue: day.maximum.asUnit(units),
                        rangeName: "0-100%"
                    )
                }
            }

            ForEach(dailyStats) { day in
                if day.maximum > 0 {
                    medianMark(for: day)
                }
            }

            RuleMark(
                y: .value("Low Limit", Double(timeInRangeType.bottomThreshold).asUnit(units))
            )
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .foregroundStyle(by: .value("Range", "\(timeInRangeType.bottomThreshold.formatted(withUnits: units))"))

            RuleMark(
                y: .value("Mid Limit", Double(timeInRangeType.topThreshold).asUnit(units))
            )
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .foregroundStyle(by: .value("Range", "\(timeInRangeType.topThreshold.formatted(withUnits: units))"))

            RuleMark(
                y: .value("High Limit", Double(highLimit.asUnit(units)))
            )
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .foregroundStyle(by: .value("Range", "\(highLimit.formatted(withUnits: units))"))
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let glucoseValue = value.as(Double.self) {
                        Text(
                            units == .mmolL ?
                                glucoseValue.formatted(.number.precision(.fractionLength(1))) :
                                glucoseValue.formatted(.number.precision(.fractionLength(0)))
                        )
                        .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    StatChartUtils.axisMarkContent(for: date, selectedInterval: selectedInterval, font: .caption2)
                }
            }
        }
        .chartYScale(domain: glucoseYScaleDomain())
        .chartForegroundStyleScale([
            "0-100%": .blue.opacity(0.15),
            "10-90%": .blue.opacity(0.3),
            "25-75%": .blue.opacity(0.5),
            "Median": .blue,
            "\(timeInRangeType.bottomThreshold.formatted(withUnits: units))": .red,
            "\(timeInRangeType.topThreshold.formatted(withUnits: units))": .mint,
            "\(highLimit.formatted(withUnits: units))": .orange
        ])
        .chartLegend(position: .bottom, spacing: 8)
    }

    private func percentileBarMark(
        for day: GlucoseDailyPercentileStats,
        startValue: Double,
        endValue: Double,
        rangeName: String
    ) -> some ChartContent {
        BarMark(
            x: .value("Day", day.date, unit: .day),
            y: .value("Percentage", endValue - startValue)
        )
        .foregroundStyle(by: .value("Range", rangeName))
    }

    private func medianMark(for day: GlucoseDailyPercentileStats) -> some ChartContent {
        let baseDate = Calendar.current.startOfDay(for: day.date)
        let startOffset = Int(0.15 * 24 * 60)
        let endOffset = Int(0.85 * 24 * 60)

        return RuleMark(
            xStart: .value("DayStart", Calendar.current.date(byAdding: .minute, value: startOffset, to: baseDate)!),
            xEnd: .value("DayEnd", Calendar.current.date(byAdding: .minute, value: endOffset, to: baseDate)!),
            y: .value("Median", day.median.asUnit(units))
        )
        .lineStyle(StrokeStyle(lineWidth: 2))
        .foregroundStyle(by: .value("Range", "Median"))
    }

    private func spacerBarMark(for day: GlucoseDailyPercentileStats) -> some ChartContent {
        BarMark(
            x: .value("Day", day.date, unit: .day),
            y: .value("Percentage", day.minimum.asUnit(units))
        )
        .foregroundStyle(Color.clear)
    }

    private func glucoseYScaleDomain() -> ClosedRange<Double> {
        StatChartUtils.glucosePercentileYScaleDomain(for: dailyStats, highLimit: highLimit, units: units)
    }
}
