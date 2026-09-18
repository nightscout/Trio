import Charts
import SwiftUI

struct LoopBarChartView: View {
    let loopStatRecords: [LoopStatRecord]
    let selectedInterval: Stat.StateModel.StatsTimeIntervalWithCustom
    let statsData: [LoopStatsProcessedData]
    /// Whether the window covers more than one day. `.custom` can be either, and the numbers
    /// behind these bars are always per-day averages — only the label has to say so.
    let spansMultipleDays: Bool

    /// A one-day window's per-day average *is* its count, so the bare label is honest there.
    private var showsPerDayAverages: Bool {
        switch selectedInterval {
        case .day: return false
        case .custom: return spansMultipleDays
        case .month,
             .total,
             .week: return true
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Chart(statsData, id: \.category) { data in
                BarMark(
                    x: .value("Percentage", data.percentage),
                    y: .value("Category", data.category.displayName)
                )
                .cornerRadius(5)
                .foregroundStyle(data.category == .successfulLoop ? Color.blue : Color.green)
                .annotation(position: .overlay) {
                    HStack {
                        Text(annotationText(for: data))
                            .font(.callout)
                            .foregroundStyle(.white)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    if let category = value.as(String.self) {
                        AxisValueLabel {
                            Text(category)
                                .font(.footnote)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    if let percentage = value.as(Double.self) {
                        if selectedInterval != .custom || spansMultipleDays {
                            AxisValueLabel {
                                Text("\(Int(percentage))%")
                                    .font(.footnote)
                            }
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartXScale(domain: 0 ... 100)
            .frame(height: 200)
            .padding()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Looping performance bar chart"))
        }
    }

    private func annotationText(for data: LoopStatsProcessedData) -> String {
        if data.category == .successfulLoop {
            return "\(data.count) " + (
                showsPerDayAverages
                    ? String(localized: "Loops per Day")
                    : String(localized: "Loops")
            )
        }
        return "\(data.count) " + (
            showsPerDayAverages
                ? String(localized: "Readings per Day")
                : String(localized: "Readings")
        )
    }
}
