import Charts
import SwiftUI

/// A static, full-range rendering of the Bolus Distribution chart for PDF export. Mirrors
/// `BolusStatsView`'s marks/colors/legend exactly, but shows every entry in the export range at
/// once instead of a scrollable window, and drops the interactive selection popover (not
/// meaningful in a static, non-interactive PDF).
struct InsulinBolusPDFChart: View {
    let stats: [BolusStats]
    let selectedInterval: Stat.StateModel.StatsTimeInterval

    private var averages: (manual: Double, smb: Double, external: Double) {
        guard !stats.isEmpty else { return (0, 0, 0) }

        var manualTotal = 0.0
        var smbTotal = 0.0
        var externalTotal = 0.0
        for stat in stats {
            manualTotal += stat.manualBolus
            smbTotal += stat.smb
            externalTotal += stat.external
        }

        let count = Double(stats.count)
        return (manualTotal / count, smbTotal / count, externalTotal / count)
    }

    private var total: Double {
        stats.reduce(0) { $0 + $1.manualBolus + $1.smb + $1.external }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView

            VStack(alignment: .trailing) {
                Text("Bolus Insulin (U)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .padding(.bottom, 4)

                chart
            }
        }
    }

    private var statsView: some View {
        Grid(alignment: .leading) {
            GridRow {
                if selectedInterval != .day {
                    Text("ø") + Text("\u{00A0}") + Text("Manual:")
                } else {
                    Text("Manual:")
                }
                Text(averages.manual.formatted(.number.precision(.fractionLength(1))))
                    + Text("\u{00A0}") + Text("U")
            }
            GridRow {
                if selectedInterval != .day {
                    Text("ø") + Text("\u{00A0}") + Text("SMB:")
                } else {
                    Text("SMB:")
                }
                Text(averages.smb.formatted(.number.precision(.fractionLength(1))))
                    + Text("\u{00A0}") + Text("U")
            }
            GridRow {
                if selectedInterval != .day {
                    Text("ø") + Text("\u{00A0}") + Text("External:")
                } else {
                    Text("External:")
                }
                Text(averages.external.formatted(.number.precision(.fractionLength(1))))
                    + Text("\u{00A0}") + Text("U")
            }
            Divider()
            GridRow {
                Text("Total:")
                Text(total.formatted(.number.precision(.fractionLength(1))))
                    + Text("\u{00A0}") + Text("U")
            }
        }
        .font(.headline)
    }

    private var chart: some View {
        Chart {
            ForEach(stats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.manualBolus)
                )
                .foregroundStyle(by: .value("Type", "Manual"))
                .position(by: .value("Type", "Boluses"))

                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.smb)
                )
                .foregroundStyle(by: .value("Type", "SMB"))
                .position(by: .value("Type", "Boluses"))

                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.external)
                )
                .foregroundStyle(by: .value("Type", "External"))
                .position(by: .value("Type", "Boluses"))
            }
        }
        .chartForegroundStyleScale([
            "SMB": Color.blue,
            "Manual": Color.teal,
            "External": Color.purple
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
            let legendItems: [(String, Color)] = [
                (String(localized: "SMB"), Color.blue),
                (String(localized: "Manual"), Color.teal),
                (String(localized: "External"), Color.purple)
            ]

            let columns = [GridItem(.adaptive(minimum: 65), spacing: 4)]

            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(legendItems, id: \.0) { item in
                    StatChartUtils.legendItem(label: item.0, color: item.1)
                }
            }
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
        .frame(height: 240)
    }
}
