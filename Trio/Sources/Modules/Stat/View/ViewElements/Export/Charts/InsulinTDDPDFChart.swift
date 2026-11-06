import Charts
import SwiftUI

/// A static, full-range rendering of the Total Daily Dose chart for PDF export. Mirrors
/// `TotalDailyDoseChart`'s marks/colors exactly, but shows every entry in the export range at
/// once instead of a scrollable window, and drops the interactive selection popover (not
/// meaningful in a static, non-interactive PDF).
struct InsulinTDDPDFChart: View {
    let stats: [TDDStats]
    let selectedInterval: Stat.StateModel.StatsTimeInterval

    private var average: Double {
        guard !stats.isEmpty else { return 0 }
        return stats.reduce(0) { $0 + $1.amount } / Double(stats.count)
    }

    private var total: Double {
        stats.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView

            VStack(alignment: .trailing) {
                Text("Total Daily Dose (U)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .padding(.bottom, 4)

                chart
            }
        }
    }

    private var statsView: some View {
        HStack {
            if selectedInterval == .day {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Average:")
                        Text(average.formatted(.number.precision(.fractionLength(1))))
                            + Text("\u{00A0}") + Text("U")
                    }
                    GridRow {
                        Text("Total:")
                        Text(total.formatted(.number.precision(.fractionLength(1))))
                            + Text("\u{00A0}") + Text("U")
                    }
                }
                .font(.headline)
            } else {
                Group {
                    Text("Average:")
                    Text(average.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                .font(.headline)
            }
            Spacer()
        }
    }

    private var chart: some View {
        Chart(stats) { stat in
            BarMark(
                x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                y: .value("Amount", stat.amount)
            )
            .foregroundStyle(Color.insulin)
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let amount = value.as(Double.self) {
                    AxisValueLabel {
                        Text(amount.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption2)
                    }
                    AxisGridLine()
                }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: selectedInterval == .day ? .hour : .day)) { value in
                if let date = value.as(Date.self) {
                    StatChartUtils.axisMarkContent(for: date, selectedInterval: selectedInterval, font: .caption2)
                }
            }
        }
        .frame(height: 220)
    }
}
