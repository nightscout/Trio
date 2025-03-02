import Charts
import SwiftUI

struct GlucoseDistributionChart: View {
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let glucoseRangeStats: [GlucoseRangeStats]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Glucose Distribution")
                .font(.headline)

            Chart(glucoseRangeStats) { range in
                ForEach(range.values, id: \.hour) { value in
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(value.hour)),
                        y: .value("Count", value.count),
                        stacking: .normalized
                    )
                    .foregroundStyle(by: .value("Range", range.name))
                }
            }
            .chartForegroundStyleScale([
                "<54": .purple.opacity(0.7),
                "54-70": .red.opacity(0.7),
                "70-140": .green,
                "140-180": .green.opacity(0.7),
                "180-200": .yellow.opacity(0.7),
                "200-220": .orange.opacity(0.7),
                ">220": .orange.opacity(0.8)
            ])
            .chartLegend(position: .bottom) {
                let legendItems: [(String, Color)] = [
                    ("<\(units == .mgdL ? Decimal(54) : 54.asMmolL)", .purple.opacity(0.7)),
                    (
                        "\(units == .mgdL ? Decimal(54) : 54.asMmolL)-\(units == .mgdL ? Decimal(70) : 70.asMmolL)",
                        .red.opacity(0.7)
                    ),
                    ("\(units == .mgdL ? Decimal(70) : 70.asMmolL)-\(units == .mgdL ? Decimal(140) : 140.asMmolL)", .green),
                    (
                        "\(units == .mgdL ? Decimal(140) : 140.asMmolL)-\(units == .mgdL ? Decimal(180) : 180.asMmolL)",
                        .green.opacity(0.7)
                    ),
                    (
                        "\(units == .mgdL ? Decimal(180) : 180.asMmolL)-\(units == .mgdL ? Decimal(200) : 200.asMmolL)",
                        .yellow.opacity(0.7)
                    ),
                    (
                        "\(units == .mgdL ? Decimal(200) : 200.asMmolL)-\(units == .mgdL ? Decimal(220) : 220.asMmolL)",
                        .orange.opacity(0.7)
                    ),
                    (">\(units == .mgdL ? Decimal(220) : 220.asMmolL)", .orange.opacity(0.8))
                ]

                let columns = [GridItem(.adaptive(minimum: 65), spacing: 4)]

                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(legendItems, id: \.0) { item in
                        legendItem(label: item.0, color: item.1)
                    }
                }
            }

            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    if let percentage = value.as(Double.self) {
                        AxisValueLabel {
                            Text((percentage / 100).formatted(.percent.precision(.fractionLength(0))))
                                .font(.footnote)
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartYAxisLabel(alignment: .trailing) {
                Text("Percentage")
                    .foregroundStyle(.primary)
                    .font(.footnote)
                    .padding(.vertical, 3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                        .font(.footnote)
                    AxisGridLine()
                }
            }
            .frame(height: 200)
        }
    }

    @ViewBuilder func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill").foregroundStyle(color)
            Text(label).foregroundStyle(Color.secondary)
        }.font(.caption2)
    }
}
