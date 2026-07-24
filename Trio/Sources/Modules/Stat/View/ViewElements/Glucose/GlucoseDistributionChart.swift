import Charts
import SwiftUI

struct GlucoseDistributionChart: View {
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let glucoseRangeStats: [GlucoseRangeStats]
    let timeInRangeType: TimeInRangeType

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
                "<54": Color.dynamicRed.opacity(0.8),
                "54-\(timeInRangeType.bottomThreshold)": Color.dynamicOrange.opacity(0.8),
                "\(timeInRangeType.bottomThreshold)-\(timeInRangeType.topThreshold)": Color.dynamicGreen.opacity(0.8),
                "\(timeInRangeType.topThreshold)-180": Color.dynamicTeal.opacity(0.8),
                "180-200": Color.dynamicBlue.opacity(0.8),
                "200-220": Color.dynamicIndigo.opacity(0.8),
                ">220": Color.dynamicPurple.opacity(0.8)
            ])
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12) {
                let legendItems: [(String, Color)] = [
                    ("<\(units == .mgdL ? Decimal(54) : 54.asMmolL)", .dynamicRed.opacity(0.8)),
                    (
                        "\(units == .mgdL ? Decimal(54) : 54.asMmolL)-\(units == .mgdL ? Decimal(timeInRangeType.bottomThreshold) : timeInRangeType.bottomThreshold.asMmolL)",
                        .dynamicOrange.opacity(0.8)
                    ),
                    (
                        "\(units == .mgdL ? Decimal(timeInRangeType.bottomThreshold) : timeInRangeType.bottomThreshold.asMmolL)-\(units == .mgdL ? Decimal(timeInRangeType.topThreshold) : timeInRangeType.topThreshold.asMmolL)",
                        .dynamicGreen.opacity(0.8)
                    ),
                    (
                        "\(units == .mgdL ? Decimal(timeInRangeType.topThreshold) : timeInRangeType.topThreshold.asMmolL)-\(units == .mgdL ? Decimal(180) : 180.asMmolL)",
                        .dynamicTeal.opacity(0.8)
                    ),
                    (
                        "\(units == .mgdL ? Decimal(180) : 180.asMmolL)-\(units == .mgdL ? Decimal(200) : 200.asMmolL)",
                        .dynamicBlue.opacity(0.8)
                    ),
                    (
                        "\(units == .mgdL ? Decimal(200) : 200.asMmolL)-\(units == .mgdL ? Decimal(220) : 220.asMmolL)",
                        .dynamicIndigo.opacity(0.8)
                    ),
                    (">\(units == .mgdL ? Decimal(220) : 220.asMmolL)", .dynamicPurple.opacity(0.8))
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
            .frame(height: 200)
        }
    }
}
