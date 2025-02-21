import Charts
import Foundation
import SwiftUI

// MARK: - Current Glucose View

struct GlucoseChartView: View {
    let glucoseValues: [(date: Date, glucose: Double, color: Color)]
    let minYAxisValue: Decimal
    let maxYAxisValue: Decimal
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
    private var filteredValues: [(date: Date, glucose: Double, color: Color)] {
        let cutoffDate = Date().addingTimeInterval(-Double(timeWindow.rawValue) * 3600)
        return glucoseValues.filter { $0.date > cutoffDate }
    }

    var glucosePointSize: CGFloat {
        switch timeWindow {
        case .threeHours: return 18
        case .sixHours: return 14
        case .twelveHours: return 10
        case .twentyFourHours: return 6
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if filteredValues.isEmpty {
                Text("No glucose readings.").font(.headline)
                Text("Check phone and CGM connectivity.").font(.caption)
            } else {
                Chart {
                    ForEach(filteredValues, id: \.date) { reading in
                        PointMark(
                            x: .value("Time", reading.date),
                            y: .value("Glucose", reading.glucose)
                        )
                        .foregroundStyle(reading.color)
                        .symbolSize(glucosePointSize)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel("\(timeWindow.rawValue) h", alignment: .topLeading)
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine(stroke: .init(lineWidth: 0.65, dash: [2, 3]))
                            .foregroundStyle(Color.white.opacity(0.25))

                        AxisValueLabel {
                            if let glucose = value.as(Double.self) {
                                Text("\(Int(glucose))")
                            }
                        }
                    }
                }
                .chartYScale(
                    domain: minYAxisValue ... maxYAxisValue
                )
                .chartPlotStyle { plotContent in
                    plotContent
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.clear)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.bottom)
            }
        }
        .scenePadding()
        .onTapGesture {
            withAnimation {
                timeWindow = timeWindow.next
            }
        }
    }
}
