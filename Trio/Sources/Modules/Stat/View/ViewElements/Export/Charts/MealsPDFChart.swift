import Charts
import SwiftUI

/// A static, full-range rendering of the Total Meals chart for PDF export. Mirrors
/// `MealStatsView`'s marks/colors/legend exactly, but shows every entry in the export range at
/// once instead of a scrollable window, and drops the interactive selection popover (not
/// meaningful in a static, non-interactive PDF).
struct MealsPDFChart: View {
    let stats: [MealStats]
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    let useFPUconversion: Bool

    private var averages: (carbs: Double, fat: Double, protein: Double) {
        guard !stats.isEmpty else { return (0, 0, 0) }

        var carbsTotal = 0.0
        var fatTotal = 0.0
        var proteinTotal = 0.0
        for stat in stats {
            carbsTotal += stat.carbs
            fatTotal += stat.fat
            proteinTotal += stat.protein
        }

        let count = Double(stats.count)
        return (carbsTotal / count, fatTotal / count, proteinTotal / count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView

            VStack(alignment: .trailing) {
                Text("Macro Nutrients (g)")
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
                Text("Carbs:")
                Text(averages.carbs.formatted(.number.precision(.fractionLength(1))))
                    + Text("\u{00A0}") + Text("g")
            }
            if useFPUconversion {
                GridRow {
                    Text("Fat:")
                    Text(averages.fat.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("g")
                }
                GridRow {
                    Text("Protein:")
                    Text(averages.protein.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("g")
                }
            }
        }
        .font(.headline)
    }

    private var chart: some View {
        Chart {
            ForEach(stats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.carbs)
                )
                .foregroundStyle(by: .value("Type", "Carbs"))
                .position(by: .value("Type", "Macros"))

                if useFPUconversion {
                    BarMark(
                        x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                        y: .value("Amount", stat.fat)
                    )
                    .foregroundStyle(by: .value("Type", "Fat"))
                    .position(by: .value("Type", "Macros"))

                    BarMark(
                        x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                        y: .value("Amount", stat.protein)
                    )
                    .foregroundStyle(by: .value("Type", "Protein"))
                    .position(by: .value("Type", "Macros"))
                }
            }
        }
        .chartForegroundStyleScale([
            "Carbs": Color.orange,
            "Fat": Color.purple,
            "Protein": Color.blue
        ])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
            let legendItems: [(String, Color)] = useFPUconversion ? [
                (String(localized: "Carbs"), Color.orange),
                (String(localized: "Fat"), Color.purple),
                (String(localized: "Protein"), Color.blue)
            ] : [(String(localized: "Carbs"), Color.orange)]

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
