import Charts
import Foundation
import SwiftUI

// MARK: - Current Glucose View

struct GlucoseChartView: View {
    let state: WatchState
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

    struct ForecastConePoint: Identifiable {
        var id: Date { date }
        var date: Date
        var min: Double
        var max: Double
    }

    struct ForecastLinePoint: Identifiable {
        var id: String { "\(type)-\(date.timeIntervalSince1970)" }
        var type: String
        var date: Date
        var value: Double
    }

    private var forecastConePoints: [ForecastConePoint] {
        guard state.showForecast, state.isForecastCone, let anchorDate = state.forecastStartDate else { return [] }

        let minForecast = state.forecastConeMin
        let maxForecast = state.forecastConeMax
        let count = min(minForecast.count, maxForecast.count)

        var pts: [ForecastConePoint] = []
        for i in 0 ..< count {
            let date = anchorDate.addingTimeInterval(TimeInterval(i * 300))
            let yMin = minForecast[i]
            let yMax = maxForecast[i]

            if yMin == yMax {
                pts.append(ForecastConePoint(date: date, min: yMin - 1, max: yMax + 1))
            } else {
                pts.append(ForecastConePoint(date: date, min: yMin, max: yMax))
            }
        }
        return pts
    }

    private var forecastLinePoints: [ForecastLinePoint] {
        guard state.showForecast, !state.isForecastCone, let anchorDate = state.forecastStartDate else { return [] }

        var pts: [ForecastLinePoint] = []
        for (type, values) in state.forecastLines {
            for i in 0 ..< values.count {
                let date = anchorDate.addingTimeInterval(TimeInterval(i * 300))
                pts.append(ForecastLinePoint(type: type, date: date, value: values[i]))
            }
        }
        return pts
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

                    if state.showForecast {
                        if state.isForecastCone {
                            ForEach(forecastConePoints) { pt in
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    yStart: .value("Min", pt.min),
                                    yEnd: .value("Max", pt.max)
                                )
                                .foregroundStyle(Color.insulin.opacity(0.3))
                            }
                        } else {
                            ForEach(forecastLinePoints) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Value", pt.value),
                                    series: .value("Type", pt.type)
                                )
                                .foregroundStyle(by: .value("Type", pt.type))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                            }
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "iob": Color.insulin,
                    "zt": Color.ZT,
                    "cob": Color.loopYellow,
                    "uam": Color.UAM
                ])
                .chartLegend(.hidden)
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
