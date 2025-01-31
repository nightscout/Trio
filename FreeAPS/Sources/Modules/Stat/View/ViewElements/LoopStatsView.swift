import Charts
import SwiftUI

struct LoopStatsView: View {
    let loopStatRecords: [LoopStatRecord]
    let selectedDuration: Stat.StateModel.Duration
    let statsData: [(category: String, count: Int, percentage: Double)]

    var body: some View {
        VStack(spacing: 20) {
            Chart(statsData, id: \.category) { data in
                BarMark(
                    x: .value("Percentage", data.percentage),
                    y: .value("Category", data.category)
                )
                .cornerRadius(5)
                .foregroundStyle(data.category == "Successful Loops" ? Color.blue.gradient : Color.green.gradient)
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

    private func annotationText(for data: (category: String, count: Int, percentage: Double)) -> String {
        if data.category == "Loop Success Rate" {
            switch selectedDuration {
            case .Day,
                 .Today:
                return "\(data.count) Loops"
            case .Month,
                 .Total,
                 .Week:
                let maxLoopsPerDay = 288.0
                let averageLoopsPerDay = Double(data.count) / maxLoopsPerDay * 100
                return "\(Int(round(averageLoopsPerDay))) Loops per day"
            }
        } else {
            // For Glucose Count, show different text based on duration
            switch selectedDuration {
            case .Day,
                 .Today:
                return "\(data.count) Readings"
            case .Month,
                 .Total,
                 .Week:
                return "\(data.count) Readings per day"
            }
        }
    }
}
