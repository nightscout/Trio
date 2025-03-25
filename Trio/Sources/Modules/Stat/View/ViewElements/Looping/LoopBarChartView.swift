import Charts
import SwiftUI

struct LoopBarChartView: View {
    let loopStatRecords: [LoopStatRecord]
    let selectedInterval: Stat.StateModel.StatsTimeIntervalWithToday
    let statsData: [LoopStatsProcessedData]

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
                        AxisValueLabel {
                            Text("\(Int(percentage))%")
                                .font(.footnote)
                        }
                        AxisGridLine()
                    }
                }
            }
            .chartXScale(domain: 0 ... 100)
            .frame(height: 200)
            .padding()
        }
    }

    private func annotationText(for data: LoopStatsProcessedData) -> String {
        if data.category == .successfulLoop {
            switch selectedInterval {
            case .day,
                 .today:
                return "\(data.count) " + String(localized: "Loops")
            case .month,
                 .total,
                 .week:
                return "\(data.count) " + String(localized: "Loops per Day")
            }
        } else {
            // For Glucose Count, show different text based on duration
            switch selectedInterval {
            case .day,
                 .today:
                return "\(data.count) " + String(localized: "Readings")
            case .month,
                 .total,
                 .week:
                return "\(data.count) " + String(localized: "Readings per Day")
            }
        }
    }
}
