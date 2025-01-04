import Charts
import Foundation
import SwiftUI

// MARK: - Current Glucose View

struct GlucoseChartView: View {
    let glucoseValues: [(date: Date, glucose: Double)]
    @State private var timeWindow: TimeWindow = .threeHours

    enum TimeWindow: Int {
        case threeHours = 3
        case sixHours = 6
        case twelveHours = 12
        case twentyFourHours = 24

        var next: TimeWindow {
            switch self {
            case .threeHours: return .sixHours
            case .sixHours: return .twelveHours
            case .twelveHours: return .twentyFourHours
            case .twentyFourHours: return .threeHours
            }
        }
    }

    // TODO: should we only change the x axis here like we do in the main chart instead of filtering the values?
    private var filteredValues: [(date: Date, glucose: Double)] {
        let cutoffDate = Date().addingTimeInterval(-Double(timeWindow.rawValue) * 3600)
        return glucoseValues.filter { $0.date > cutoffDate }
    }

    // TODO: replace hard coded values with actual settings and add dynamic color
    private func glucoseColor(_ value: Double) -> Color {
        if value > 180 {
            return .orange
        } else if value < 70 {
            return .red
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Glucose History")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Text("\(timeWindow.rawValue)h")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Chart {
                ForEach(filteredValues, id: \.date) { reading in
                    PointMark(
                        x: .value("Time", reading.date),
                        y: .value("Glucose", reading.glucose)
                    )
                    .foregroundStyle(glucoseColor(reading.glucose))
                    .symbolSize(30)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                        .font(.footnote)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let glucose = value.as(Double.self) {
                            Text("\(Int(glucose))").font(.footnote)
                        }
                    }
                }
            }
            .padding()
        }
        .onTapGesture {
            withAnimation {
                timeWindow = timeWindow.next
            }
        }
    }
}
