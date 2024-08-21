import Charts
import CoreData
import Foundation
import SwiftUI

struct ForeCastChart: View {
    @StateObject var state: Bolus.StateModel
    @Environment(\.colorScheme) var colorScheme
    @Binding var units: GlucoseUnits

    @State private var startMarker = Date(timeIntervalSinceNow: -4 * 60 * 60)

    private var endMarker: Date {
        state
            .displayForecastsAsLines ? Date(timeIntervalSinceNow: TimeInterval(hours: 3)) :
            Date(timeIntervalSinceNow: TimeInterval(
                Int(1.5) * 5 * state
                    .minCount * 60
            )) // min is 1.5h -> (1.5*1h = 1.5*(5*12*60))
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        if units == .mmolL {
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 1
            formatter.roundingMode = .halfUp
        } else {
            formatter.maximumFractionDigits = 0
        }
        return formatter
    }

    var body: some View {
        VStack {
            forecastChart
                .padding(.vertical, 3)
            HStack {
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 16, weight: .bold))

                if let eventualBG = state.simulatedDetermination?.eventualBG {
                    HStack {
                        Text(
                            glucoseFormatter
                                .string(from: (units == .mgdL ? Decimal(eventualBG) : eventualBG.asMmolL) as NSNumber) ?? "--"
                        )
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        Text("\(units.rawValue)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("---")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    Text("\(units.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var forecastChart: some View {
        Chart {
            drawGlucose()
            drawCurrentTimeMarker()

            if state.displayForecastsAsLines {
                drawForecastLines()
            } else {
                drawForecastCone()
            }
        }
        .chartXAxis { forecastChartXAxis }
        .chartXScale(domain: startMarker ... endMarker)
        .chartYAxis { forecastChartYAxis }
        .chartYScale(domain: units == .mgdL ? 0 ... 300 : 0.asMmolL ... 300.asMmolL)
        .backport.chartForegroundStyleScale(state: state)
    }

    private func drawGlucose() -> some ChartContent {
        ForEach(state.glucoseFromPersistence) { item in
            if item.glucose > Int(state.highGlucose) {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL)
                )
                .foregroundStyle(Color.orange.gradient)
                .symbolSize(20)
            } else if item.glucose < Int(state.lowGlucose) {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL)
                )
                .foregroundStyle(Color.red.gradient)
                .symbolSize(20)
            } else {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL)
                )
                .foregroundStyle(Color.green.gradient)
                .symbolSize(20)
            }
        }
    }

    private func timeForIndex(_ index: Int32) -> Date {
        let currentTime = Date()
        let timeInterval = TimeInterval(index * 300)
        return currentTime.addingTimeInterval(timeInterval)
    }

    private func drawForecastCone() -> some ChartContent {
        ForEach(0 ..< max(state.minForecast.count, state.maxForecast.count), id: \.self) { index in
            if index < state.minForecast.count, index < state.maxForecast.count {
                let yMinValue = Decimal(state.minForecast[index]) <= 300 ? Decimal(state.minForecast[index]) : Decimal(300)
                let yMaxValue = Decimal(state.maxForecast[index]) <= 300 ? Decimal(state.maxForecast[index]) : Decimal(300)

                AreaMark(
                    x: .value("Time", timeForIndex(Int32(index)) <= endMarker ? timeForIndex(Int32(index)) : endMarker),
                    yStart: .value("Min Value", units == .mgdL ? yMinValue : yMinValue.asMmolL),
                    yEnd: .value("Max Value", units == .mgdL ? yMaxValue : yMaxValue.asMmolL)
                )
                .foregroundStyle(Color.blue.opacity(0.5))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    private func drawForecastLines() -> some ChartContent {
        let predictions = state.predictionsForChart

        // Prepare the prediction data with only the first 36 values, i.e. 3 hours in the future
        let predictionData = [
            ("iob", predictions?.iob?.prefix(36)),
            ("zt", predictions?.zt?.prefix(36)),
            ("cob", predictions?.cob?.prefix(36)),
            ("uam", predictions?.uam?.prefix(36))
        ]

        return ForEach(predictionData, id: \.0) { name, values in
            if let values = values {
                ForEach(values.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Time", timeForIndex(Int32(index))),
                        y: .value("Value", units == .mgdL ? Decimal(values[index]) : Decimal(values[index]).asMmolL)
                    )
                    .foregroundStyle(by: .value("Prediction Type", name))
                }
            }
        }
    }

    private func drawCurrentTimeMarker() -> some ChartContent {
        RuleMark(
            x: .value(
                "",
                Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970)),
                unit: .second
            )
        ).lineStyle(.init(lineWidth: 2, dash: [3])).foregroundStyle(Color(.systemGray2))
    }

    private var forecastChartXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
            AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                .font(.footnote)
                .foregroundStyle(Color.primary)
        }
    }

    private var forecastChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { _ in
            AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            AxisTick(length: 3, stroke: .init(lineWidth: 3)).foregroundStyle(Color.secondary)
            AxisValueLabel().font(.footnote).foregroundStyle(Color.primary)
        }
    }
}
