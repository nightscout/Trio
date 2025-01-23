import Charts
import SwiftUI

struct LoopStatsView: View {
    let loopStatRecords: [LoopStatRecord]
    let selectedDuration: Stat.StateModel.Duration
    let groupedStats: [LoopStatsByPeriod]
    private let calendar = Calendar.current

    private var medianLoopDuration: Double {
        groupedStats.first?.medianDuration ?? 0
    }

    var body: some View {
        VStack(spacing: 20) {
            loopDurationChart
            Divider()
            loopStatsChart
        }
    }

    private var loopDurationChart: some View {
        Chart {
            ForEach(loopStatRecords, id: \.id) { record in
                LineMark(
                    x: .value("Time", record.start ?? Date(), unit: .hour),
                    y: .value("Duration", record.duration / 1000)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.blue.opacity(0.6))
            }

            RuleMark(
                y: .value("Median", medianLoopDuration / 1000)
            )
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .foregroundStyle(.orange)
            .annotation(position: .top, alignment: .trailing) {
                Text("\((medianLoopDuration / 1000).formatted(.number.precision(.fractionLength(1)))) s")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .chartYAxis {
            loopDurationChartYAxisMarks
        }
        .chartYAxisLabel(alignment: .leading) {
            Text("Loop duration")
                .foregroundStyle(.primary)
                .font(.caption)
                .padding(.vertical, 3)
        }
        .chartXAxis {
            loopDurationAxisMarks
        }
        .frame(height: 200)
        .padding(.horizontal)
    }

    private var loopDurationAxisMarks: some AxisContent {
        AxisMarks { value in
            if let date = value.as(Date.self) {
                AxisValueLabel {
                    switch selectedDuration {
                    case .Day,
                         .Today:
                        Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    case .Week:
                        Text(date, format: .dateTime.weekday(.abbreviated))
                    case .Month,
                         .Total:
                        Text(date, format: .dateTime.day().month(.defaultDigits))
                    }
                }
                AxisGridLine()
            }
        }
    }

    private var loopDurationChartYAxisMarks: some AxisContent {
        AxisMarks(position: .leading) { value in
            if let duration = value.as(Double.self) {
                AxisValueLabel {
                    Text("\(duration.formatted(.number.precision(.fractionLength(1)))) s")
                        .font(.caption)
                }
                AxisGridLine()
            }
        }
    }

    private var loopStatsChart: some View {
        Chart {
            ForEach(groupedStats) { stat in
                // Stacked Bar Chart first (will be in background)
                // Succeeded Loops
                BarMark(
                    x: .value("Time", stat.period, unit: .day),
                    y: .value("Successful", stat.successPercentage)
                )
                .foregroundStyle(Color.green.opacity(0.9))
                .foregroundStyle(by: .value("Type", "Success"))
//                .zIndex(1)

                // Failed Loops
                BarMark(
                    x: .value("Time", stat.period, unit: .day),
                    y: .value("Failed", stat.failurePercentage)
                )
                .foregroundStyle(Color.red.opacity(0.9))
                .foregroundStyle(by: .value("Type", "Failed"))
//                .zIndex(1)

                // Dotted Line Mark showing the daily Glucose counts (will overlay the bars)
                LineMark(
                    x: .value("Time", stat.period, unit: .day),
                    y: .value("Glucose Count", Double(stat.glucoseCount) / 288.0 * 100)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(by: .value("Type", "Glucose Count"))
//                .zIndex(2)

                PointMark(
                    x: .value("Time", stat.period, unit: .day),
                    y: .value("Glucose Count", Double(stat.glucoseCount) / 288.0 * 100)
                )
                .foregroundStyle(Color.blue)
                .symbolSize(50)
                .foregroundStyle(by: .value("Type", "Glucose Count"))
//                .zIndex(3)
            }
        }
        .chartForegroundStyleScale([
            "Success": Color.green,
            "Failed": Color.red,
            "Glucose Count": Color.blue
        ])
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let percent = value.as(Double.self) {
                    AxisValueLabel {
                        Text("\(percent.formatted(.number.precision(.fractionLength(0))))%")
                            .font(.caption)
                    }
                    AxisGridLine()
                }
            }

            let maxPossibleReadings = 288.0
            let strideBy = 4.0
            let defaultStride = Array(stride(from: 0, to: 100, by: 100 / strideBy))
            let glucoseStride = Array(stride(from: 0, through: maxPossibleReadings, by: maxPossibleReadings / strideBy))

            AxisMarks(position: .trailing, values: defaultStride) { axis in
                let value = glucoseStride[axis.index]
                AxisValueLabel("\(Int(value))", centered: true)
                    .font(.caption)
            }
        }
        .chartYAxisLabel(alignment: .leading) {
            Text("Loop Success Rate")
                .foregroundStyle(.primary)
                .font(.caption)
                .padding(.vertical, 3)
        }
        .chartXAxis {
            statsAxisMarks
        }
        .frame(height: 200)
        .padding(.horizontal)
    }

    private var statsAxisMarks: some AxisContent {
        AxisMarks { value in
            if let date = value.as(Date.self) {
                AxisValueLabel {
                    switch selectedDuration {
                    case .Day,
                         .Today,
                         .Week:
                        Text(date, format: .dateTime.weekday(.abbreviated))
                    case .Month,
                         .Total:
                        Text(date, format: .dateTime.day().month(.defaultDigits))
                    }
                }
                AxisGridLine()
            }
        }
    }
}
