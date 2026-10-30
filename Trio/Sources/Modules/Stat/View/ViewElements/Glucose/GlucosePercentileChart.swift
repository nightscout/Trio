import Charts
import SwiftUI

struct GlucosePercentileChart: View {
    let timeInRangeType: TimeInRangeType
    let units: GlucoseUnits
    let hourlyStats: [HourlyStats]
    let isToday: Bool

    @State private var selection: Date?

    private var selectedStats: HourlyStats? {
        guard let selection = selection else { return nil }

        if isToday && selection > Date() {
            return nil
        }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selection)
        return hourlyStats.first { Int($0.hour) == hour }
    }

    private var minYValue: Double {
        40.0.asUnit(units)
    }

    private var maxYValue: Double {
        let topLimit = 400.0.asUnit(units)
        let validStats = hourlyStats.filter { $0.median > 0 }
        guard !validStats.isEmpty else { return topLimit }
        let maxPercentile90 = validStats.map(\.percentile90).max() ?? topLimit
        return max(maxPercentile90.asUnit(units), Double(GlucoseBand.inRangeThreshold).asUnit(units))
    }

    var body: some View {
        let thresholds = StatChartUtils.glucoseThresholds(timeInRangeType: timeInRangeType, units: units)

        let seriesScale: [(label: String, color: Color)] = [
            ("10-90%", .blue.opacity(0.3)),
            ("25-75%", .blue.opacity(0.5)),
            ("Median", .blue)
        ] + thresholds.map { ($0.label, $0.color) }
        VStack(alignment: .leading, spacing: 8) {
            Text("Ambulatory Glucose Profile (AGP)")
                .font(.headline)

            Chart {
                ForEach(hourlyStats, id: \.hour) { stats in
                    let hourDate = Calendar.current.dateForChartHour(stats.hour)
                    AreaMark(
                        x: .value("Hour", hourDate),
                        yStart: .value("10th Percentile", stats.percentile10.asUnit(units)),
                        yEnd: .value("90th Percentile", stats.percentile90.asUnit(units)),
                        series: .value("10-90", "10-90")
                    )
                    .foregroundStyle(by: .value("Series", "10-90%"))
                    .opacity(stats.median > 0 ? 0.3 : 0)

                    AreaMark(
                        x: .value("Hour", hourDate),
                        yStart: .value("25th Percentile", stats.percentile25.asUnit(units)),
                        yEnd: .value("75th Percentile", stats.percentile75.asUnit(units)),
                        series: .value("25-75", "25-75")
                    )
                    .foregroundStyle(by: .value("Series", "25-75%"))
                    .opacity(stats.median > 0 ? 0.5 : 0)

                    if stats.median > 0 {
                        LineMark(
                            x: .value("Hour", hourDate),
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
                            StatSelectionPopover(
                                title: StatChartUtils.hourRangeText(for: selection),
                                tint: .blue
                            ) {
                                Grid(alignment: .leading) {
                                    StatChartUtils.popoverRow(
                                        label: "Median:",
                                        formattedValue: selectedStats.median.formattedAsGlucose(for: units),
                                        unit: LocalizedStringKey(units.rawValue)
                                    )
                                    StatChartUtils.popoverRow(
                                        label: "90%:",
                                        formattedValue: selectedStats.percentile90.formattedAsGlucose(for: units),
                                        unit: LocalizedStringKey(units.rawValue)
                                    )
                                    StatChartUtils.popoverRow(
                                        label: "75%:",
                                        formattedValue: selectedStats.percentile75.formattedAsGlucose(for: units),
                                        unit: LocalizedStringKey(units.rawValue)
                                    )
                                    StatChartUtils.popoverRow(
                                        label: "25%:",
                                        formattedValue: selectedStats.percentile25.formattedAsGlucose(for: units),
                                        unit: LocalizedStringKey(units.rawValue)
                                    )
                                    StatChartUtils.popoverRow(
                                        label: "10%:",
                                        formattedValue: selectedStats.percentile10.formattedAsGlucose(for: units),
                                        unit: LocalizedStringKey(units.rawValue)
                                    )
                                }
                            }
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
                Text(LocalizedStringKey(units.rawValue))
                    .foregroundStyle(.primary)
                    .font(.footnote)
                    .padding(.vertical, 3)
            }
            .chartXAxis { StatChartUtils.timeOfDayAxisMarks() }
            .chartXSelection(value: $selection)
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Glucose percentile chart"))
        }
    }
}
