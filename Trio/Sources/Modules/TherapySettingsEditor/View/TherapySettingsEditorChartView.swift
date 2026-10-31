import Charts
import SwiftUI

extension TherapySettingsEditor {
    struct ChartView: View {
        @Binding var items: [Item]
        var therapyType: TherapyType
        var unit: Unit

        @State private var now = Date()
        @State private var refreshUI = UUID()

        var body: some View {
            Chart {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let displayValue = displayValue(item.value)

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

                    if therapyType.chartShowsArea {
                        RectangleMark(
                            xStart: .value("start", startDate),
                            xEnd: .value("end", endDate),
                            yStart: .value("rate-start", displayValue),
                            yEnd: .value("rate-end", 0)
                        ).foregroundStyle(
                            .linearGradient(
                                colors: [
                                    therapyType.chartColor.opacity(0.6),
                                    therapyType.chartColor.opacity(0.1)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        ).alignsMarkStylesWithPlotArea()
                    }

                    LineMark(x: .value("End Date", startDate), y: .value("Rate", displayValue))
                        .lineStyle(.init(lineWidth: therapyType.chartShowsArea ? 1 : 2.5)).foregroundStyle(therapyType.chartColor)

                    LineMark(x: .value("Start Date", endDate), y: .value("Rate", displayValue))
                        .lineStyle(.init(lineWidth: therapyType.chartShowsArea ? 1 : 2.5)).foregroundStyle(therapyType.chartColor)
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
            .applyYScale(chartYScale)
        }

        private func displayValue(_ value: Decimal) -> Decimal {
            switch unit {
            case .mmolL,
                 .mmolLPerUnit:
                return value.asMmolL
            default:
                return value
            }
        }

        private var chartYScale: ClosedRange<Decimal>? {
            if let domain = therapyType.chartYScale {
                return displayValue(domain.lowerBound) ... displayValue(domain.upperBound)
            }
            return nil
        }
    }
}

private extension View {
    @ViewBuilder func applyYScale(_ domain: ClosedRange<Decimal>?) -> some View {
        if let domain {
            chartYScale(domain: domain)
        } else {
            self
        }
    }
}
