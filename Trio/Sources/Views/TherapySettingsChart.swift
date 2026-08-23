import Charts
import SwiftUI

struct TherapySettingsChart: View {
    @Binding var items: [TherapySettingItem]
    var color: Color
    var displayValueSelector: (TherapySettingItem) -> Decimal
    var showsArea: Bool = true
    var yScale: ClosedRange<Decimal>?

    @State private var now = Date()
    @State private var refreshUI = UUID()

    var body: some View {
        Chart {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let displayValue = displayValueSelector(item)

                let startDate = Calendar.current
                    .startOfDay(for: now)
                    .addingTimeInterval(item.time)

                var offset: TimeInterval {
                    if items.count > index + 1 {
                        return items[index + 1].time
                    } else {
                        return (60 * 60 * 24) // end of day
                    }
                }

                let endDate = Calendar.current.startOfDay(for: now).addingTimeInterval(offset)

                if showsArea {
                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", displayValue),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: [
                                color.opacity(0.6),
                                color.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()
                }

                LineMark(x: .value("End Date", startDate), y: .value("Rate", displayValue))
                    .lineStyle(.init(lineWidth: showsArea ? 1 : 2.5)).foregroundStyle(color)

                LineMark(x: .value("Start Date", endDate), y: .value("Rate", displayValue))
                    .lineStyle(.init(lineWidth: showsArea ? 1 : 2.5)).foregroundStyle(color)
            }
        }
        .id(refreshUI) // Force chart update
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour())
                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        .chartXScale(
            domain: Calendar.current.startOfDay(for: now) ... Calendar.current.startOfDay(for: now)
                .addingTimeInterval(60 * 60 * 24)
        )
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        .applyYScale(yScale)
    }
}

extension View {
    @ViewBuilder func applyYScale(_ domain: ClosedRange<Decimal>?) -> some View {
        if let domain {
            chartYScale(domain: domain)
        } else {
            self
        }
    }
}

#Preview {
    // TherapySettingsChart(items: [])
}
