import Charts
import SwiftUI

struct GlucoseDistributionChart: View {
    let highLimit: Decimal
    let units: GlucoseUnits
    let glucoseRangeStats: [GlucoseRangeStats]
    let timeInRangeType: TimeInRangeType

    var body: some View {
        let bands = GlucoseBand.allCases

        let infoFor: (GlucoseBand) -> (label: String, color: Color) = {
            StatChartUtils.glucoseBandDisplayInfo(for: $0, units: units, timeInRangeType: timeInRangeType, highLimit: highLimit)
        }

        VStack(alignment: .leading, spacing: 8) {
            Chart(glucoseRangeStats) { range in
                ForEach(range.values, id: \.hour) { value in
                    AreaMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(value.hour)),
                        y: .value("Share", value.share)
                    )
                    .foregroundStyle(by: .value("Range", infoFor(range.band).label))
                }
            }
            .chartForegroundStyleScale(
                domain: bands.map { infoFor($0).label },
                range: bands.map { infoFor($0).color.opacity(0.8) }
            )
            .chartYScale(domain: 0 ... 100)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    if let percentage = value.as(Double.self) {
                        AxisValueLabel {
                            Text(StatChartUtils.formatPercentage(percentage, fractionDigits: 0))
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
