import Charts
import SwiftUI

struct GlucoseDistributionChart: View {
    let units: GlucoseUnits
    let glucoseRangeStats: [GlucoseRangeStats]
    let timeInRangeType: TimeInRangeType

    var body: some View {
        let bandInfos = GlucoseBand.allCases.map {
            (label: $0.rangeLabel(units: units, timeInRangeType: timeInRangeType), color: $0.color.opacity(0.8))
        }

        VStack(alignment: .leading, spacing: 8) {
            Chart(glucoseRangeStats) { range in
                let label = range.band.rangeLabel(units: units, timeInRangeType: timeInRangeType)
                ForEach(range.values, id: \.hour) { value in
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(value.hour)),
                        y: .value("Share", value.share)
                    )
                    .foregroundStyle(by: .value("Range", label))
                }
            }
            .chartForegroundStyleScale(
                domain: bandInfos.map(\.label),
                range: bandInfos.map(\.color)
            )
            .chartYScale(domain: 0 ... 100)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    if let percentage = value.as(Double.self) {
                        AxisValueLabel {
                            Text(StatChartUtils.formatPercentage(percentage, fractionLength: 0))
                                .font(.footnote)
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartXAxis { StatChartUtils.timeOfDayAxisMarks() }
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Glucose distribution by time of day chart"))
        }
    }
}
