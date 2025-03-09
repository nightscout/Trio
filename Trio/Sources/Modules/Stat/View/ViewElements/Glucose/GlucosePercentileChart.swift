import Charts
import SwiftUI

/// A view that displays an Ambulatory Glucose Profile (AGP) chart.
///
/// This chart visualizes glucose percentile statistics over a 24-hour period.
/// It includes the 10-90 percentile, 25-75 percentile, median glucose values,
/// and high/low glucose limits.
struct GlucosePercentileChart: View {
    /// The list of stored glucose values.
    let glucose: [GlucoseStored]
    /// The upper glucose limit for the chart.
    let highLimit: Decimal
    /// The lower glucose limit for the chart.
    let lowLimit: Decimal
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ambulatory Glucose Profile (AGP)")
                .font(.headline)

            Chart {
                // Statistical view for longer periods
                ForEach(hourlyStats, id: \.hour) { stats in
                    // 10-90 percentile area
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        yStart: .value("10th Percentile", stats.percentile10),
                        yEnd: .value("90th Percentile", stats.percentile90),
                        series: .value("10-90", "10-90")
                    )
                    .foregroundStyle(by: .value("Series", "10-90"))
                    .opacity(stats.median > 0 ? 0.3 : 0)

                    // 25-75 percentile area
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        yStart: .value("25th Percentile", stats.percentile25),
                        yEnd: .value("75th Percentile", stats.percentile75),
                        series: .value("25-75", "25-75")
                    )
                    .foregroundStyle(by: .value("Series", "25-75"))
                    .opacity(stats.median > 0 ? 0.5 : 0)

                    // Median line
                    if stats.median > 0 {
                        LineMark(
                            x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                            y: .value("Median", stats.median),
                            series: .value("Median", "Median")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(by: .value("Series", "Median"))
                    }
                }

                // High/Low limit lines
                RuleMark(y: .value("High Limit", Double(highLimit)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(by: .value("Series", "High"))

                RuleMark(y: .value("Low Limit", Double(lowLimit)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(by: .value("Series", "Low"))

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
            .chartForegroundStyleScale([
                "10-90": Color.blue.opacity(0.3),
                "25-75": Color.blue.opacity(0.5),
                "Median": Color.blue,
                "High": Color.orange,
                "Low": Color.red
            ])
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
                let legendItems: [(String, Color)] = [
                    ("10-90%", Color.blue.opacity(0.3)),
                    ("20-75%", Color.blue.opacity(0.5)),
                    (String(localized: "Median"), Color.blue),
                    (String(localized: "High Threshold"), Color.orange),
                    (String(localized: "Low Threshold"), Color.red)
                ]

                let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(legendItems, id: \.0) { item in
                        StatChartUtils.legendItem(label: item.0, color: item.1)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    if let glucose = value.as(Double.self) {
                        AxisValueLabel {
                            Text(
                                units == .mmolL ? glucose.asMmolL.formatted(.number.precision(.fractionLength(0))) : glucose
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
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    if let date = value.as(Date.self) {
                        let hour = Calendar.current.component(.hour, from: date)
                        switch hour {
                        case 0,
                             12:
                            AxisValueLabel(format: .dateTime.hour())
                        default:
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                        }

                        AxisGridLine()
                    }
                }
            }
            .chartXSelection(value: $selection.animation(.easeInOut))
            .frame(height: 200)
        }
    }
}

/// A popover view displaying detailed glucose statistics for a selected time.
struct AGPSelectionPopover: View {
    let stats: HourlyStats
    let time: Date
    let units: GlucoseUnits

    @Environment(\.colorScheme) var colorScheme

    private var timeText: String {
        if let hour = Calendar.current.dateComponents([.hour], from: time).hour {
            return "\(hour):00-\(hour + 1):00"
        } else {
            return time.formatted(.dateTime.hour().minute())
        }
    }

    /// A helper function to format glucose values based on the selected unit.
    private func formattedGlucoseValue(_ value: Double) -> String {
        units == .mmolL ? value.formattedAsMmolL :
            value.formatted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeText).bold().font(.subheadline)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("Median:").bold()
                    Text(formattedGlucoseValue(stats.median))
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("90%:").bold()
                    Text(formattedGlucoseValue(stats.percentile90))
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("75%:").bold()
                    Text(formattedGlucoseValue(stats.percentile75))
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("25%:").bold()
                    Text(formattedGlucoseValue(stats.percentile25))
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("10%:").bold()
                    Text(formattedGlucoseValue(stats.percentile10))
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

private extension Calendar {
    func startOfHour(for date: Date) -> Date {
        let components = dateComponents([.year, .month, .day, .hour], from: date)
        return self.date(from: components) ?? date
    }
}
