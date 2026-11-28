import Charts
import SwiftUI

/// 24-hour step chart of a therapy setting schedule. Used by the settings editors and the PDF export.
struct TherapyProfileChart: View {
    struct Entry {
        /// Seconds after midnight.
        let start: TimeInterval
        let value: Decimal
    }

    /// Sorted by `start`. Each entry runs until the next one starts, the last until midnight.
    let entries: [Entry]
    let color: Color
    var fillsArea: Bool = true
    /// Gradients render opaque in PDFs, so the export uses a flat fill.
    var usesGradientFill: Bool = true
    var lineWidth: CGFloat = 1
    var yDomain: ClosedRange<Decimal>?
    let accessibilityLabel: Text

    private let dayStart = Calendar.current.startOfDay(for: Date())

    var body: some View {
        if let yDomain {
            chart.chartYScale(domain: yDomain)
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let startDate = dayStart.addingTimeInterval(entry.start)
                let endDate = dayStart.addingTimeInterval(
                    index + 1 < entries.count ? entries[index + 1].start : 24 * 60 * 60
                )

                if fillsArea {
                    let area = RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", entry.value),
                        yEnd: .value("rate-end", 0)
                    )
                    if usesGradientFill {
                        area.foregroundStyle(
                            .linearGradient(
                                colors: [color.opacity(0.6), color.opacity(0.1)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        ).alignsMarkStylesWithPlotArea()
                    } else {
                        area.foregroundStyle(color.opacity(0.25))
                    }
                }

                LineMark(x: .value("End Date", startDate), y: .value("Value", entry.value))
                    .lineStyle(.init(lineWidth: lineWidth)).foregroundStyle(color)

                LineMark(x: .value("Start Date", endDate), y: .value("Value", entry.value))
                    .lineStyle(.init(lineWidth: lineWidth)).foregroundStyle(color)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour())
                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        .chartXScale(domain: dayStart ... dayStart.addingTimeInterval(24 * 60 * 60))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
