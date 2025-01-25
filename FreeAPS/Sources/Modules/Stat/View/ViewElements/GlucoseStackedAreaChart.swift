import Charts
import SwiftUI

struct GlucoseStackedAreaChart: View {
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let lowLimit: Decimal
    let isToday: Bool
    let units: GlucoseUnits
    let glucoseRangeStats: [GlucoseRangeStats]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartYAxisLabel(alignment: .leading) {
                Text("Percentage")
                    .foregroundStyle(.primary)
                    .font(.caption)
                    .padding(.vertical, 3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                    AxisGridLine()
                }
            }
            .frame(height: 200)
        }
    }
}
