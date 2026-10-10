import Charts
import SwiftUI

/// A view that displays an Ambulatory Glucose Profile (AGP) chart.
///
/// This chart visualizes glucose percentile statistics over a 24-hour period.
/// It includes the 10-90 percentile, 25-75 percentile, median glucose values,
/// and high/low glucose limits.
struct GlucosePercentileChart: View {
    /// The upper glucose limit for the chart.
    let highLimit: Decimal
    /// TITR or TING
    let timeInRangeType: TimeInRangeType
    /// The units used for glucose measurement (mg/dL or mmol/L).
    let units: GlucoseUnits
    /// The hourly glucose statistics.
    let hourlyStats: [HourlyStats]
    /// Flag indicating whether the chart represents today's data.
    let isToday: Bool

    /// The currently selected hour in the chart.
    @State private var selection: Date? = nil

    /// Retrieves the hourly statistics for the selected time.
    private var selectedStats: HourlyStats? {
        guard let selection = selection else { return nil }

        if isToday && selection > Date() {
            return nil
        }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selection)
        return hourlyStats.first { Int($0.hour) == hour }
    }

    /// The minimum Y-axis value based on the lowest possible cgm reading
    private var minYValue: Double {
        40.0.asUnit(units)
    }

    /// The maximum Y-axis value based on the highest 90th percentile
    private var maxYValue: Double {
        let topLimit = 400.0.asUnit(units)
        let validStats = hourlyStats.filter { $0.median > 0 }
        guard !validStats.isEmpty else { return topLimit }
        let maxPercentile90 = validStats.map(\.percentile90).max() ?? topLimit
        return max(maxPercentile90.asUnit(units), Double(highLimit.asUnit(units)))
    }

    var body: some View {
        let thresholds = StatChartUtils.glucoseThresholds(timeInRangeType: timeInRangeType, highLimit: highLimit, units: units)

        let seriesScale: [(label: String, color: Color)] = [
            ("10-90%", .blue.opacity(0.3)),
            ("25-75%", .blue.opacity(0.5)),
            ("Median", .blue)
        ] + thresholds.map { ($0.label, $0.color) }
        VStack(alignment: .leading, spacing: 8) {
            Text("Ambulatory Glucose Profile (AGP)")
                .font(.headline)

            Chart {
                // Statistical view for longer periods
                ForEach(hourlyStats, id: \.hour) { stats in
                    // 10-90 percentile area
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        yStart: .value("10th Percentile", stats.percentile10.asUnit(units)),
                        yEnd: .value("90th Percentile", stats.percentile90.asUnit(units)),
                        series: .value("10-90", "10-90")
                    )
                    .foregroundStyle(by: .value("Series", "10-90%"))
                    .opacity(stats.median > 0 ? 0.3 : 0)

                    // 25-75 percentile area
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        yStart: .value("25th Percentile", stats.percentile25.asUnit(units)),
                        yEnd: .value("75th Percentile", stats.percentile75.asUnit(units)),
                        series: .value("25-75", "25-75")
                    )
                    .foregroundStyle(by: .value("Series", "25-75%"))
                    .opacity(stats.median > 0 ? 0.5 : 0)

                    // Median line
                    if stats.median > 0 {
                        LineMark(
                            x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                            y: .value("Median", stats.median.asUnit(units)),
                            series: .value("Median", "Median")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(by: .value("Series", "Median"))
                    }
                }

                ForEach(thresholds, id: \.label) { threshold in
                    RuleMark(y: .value("Limit", threshold.value))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .foregroundStyle(by: .value("Series", threshold.label))
                }
                if let selectedStats, let selection {
                    RuleMark(x: .value("Selection", selection))
                        .foregroundStyle(Color.blue.opacity(0.5))
                        .annotation(
                            position: .top,
                            spacing: 0,
                            overflowResolution: .init(x: .fit, y: .disabled)
                        ) {
                            AGPSelectionPopover(
                                stats: selectedStats,
                                time: selection,
                                units: units
                            )
                        }
                }
            }
            .chartForegroundStyleScale(
                domain: seriesScale.map(\.label),
                range: seriesScale.map(\.color)
            )
            .chartYScale(domain: minYValue ... maxYValue)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    if let glucose = value.as(Double.self) {
                        AxisValueLabel {
                            Text(
                                units == .mmolL ? glucose.formatted(.number.precision(.fractionLength(1))) : glucose
                                    .formatted(.number.precision(.fractionLength(0)))
                            )
                            .font(.footnote)
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartYAxisLabel(alignment: .trailing) {
                Text("\(units.rawValue)")
                    .foregroundStyle(.primary)
                    .font(.footnote)
                    .padding(.vertical, 3)
            }
            .chartXAxis { StatChartUtils.timeOfDayAxisMarks() }
            .chartXSelection(value: $selection.animation(.easeInOut))
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Glucose percentile chart"))
        }
    }
}

/// A popover view displaying detailed glucose statistics for a selected time.
struct AGPSelectionPopover: View {
    let stats: HourlyStats
    let time: Date
    let units: GlucoseUnits

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(StatChartUtils.hourRangeText(for: time)).bold().font(.subheadline)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("Median:").bold()
                    Text(stats.median.formatted(for: units))
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("90%:").bold()
                    Text(stats.percentile90.formatted(for: units))
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("75%:").bold()
                    Text(stats.percentile75.formatted(for: units))
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("25%:").bold()
                    Text(stats.percentile25.formatted(for: units))
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("10%:").bold()
                    Text(stats.percentile10.formatted(for: units))
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
            }.font(.headline)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.bgDarkBlue.opacity(0.9) : Color.white.opacity(0.95))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.blue, lineWidth: 2)
                )
        }
    }
}
