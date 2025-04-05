import Charts
import CoreData
import Foundation
import SwiftUI

struct ForecastChart: View {
    var state: Treatments.StateModel
    @Environment(\.colorScheme) var colorScheme

    @State private var startMarker = Date(timeIntervalSinceNow: -4 * 60 * 60)

    @State var selection: Date? = nil

    private var endMarker: Date {
        state
            .forecastDisplayType == .lines ? Date(timeIntervalSinceNow: TimeInterval(hours: 3)) :
            Date(timeIntervalSinceNow: TimeInterval(
                Int(1.5) * 5 * state
                    .minCount * 60
            )) // min is 1.5h -> (1.5*1h = 1.5*(5*12*60))
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        if state.units == .mmolL {
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 1
            formatter.roundingMode = .halfUp
        } else {
            formatter.maximumFractionDigits = 0
        }
        return formatter
    }

    private var selectedGlucose: GlucoseStored? {
        guard let selection = selection else { return nil }
        let range = selection.addingTimeInterval(-150) ... selection.addingTimeInterval(150)
        return state.glucoseFromPersistence.first { $0.date.map(range.contains) ?? false }
    }

    var body: some View {
        VStack {
            forecastChartLabels
                .padding(.bottom, 8)

            forecastChart
        }
    }

    private var forecastChartLabels: some View {
        HStack {
            HStack {
                Image(systemName: "fork.knife")
                Text("\(state.carbs.description) g")
            }
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.2))
            }

            Spacer()

            HStack {
                Image(systemName: "syringe.fill")
                Text("\(state.amount.description) U")
            }
            .font(.footnote)
            .foregroundStyle(.blue)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.2))
            }

            Spacer()

            HStack {
                Image(systemName: "arrow.right.circle")

                if let simulatedDetermination = state.simulatedDetermination, let eventualBG = simulatedDetermination.eventualBG {
                    eventualGlucoseBadge(for: eventualBG)
                } else if let lastDetermination = state.determination.first, let eventualBG = lastDetermination.eventualBG {
                    eventualGlucoseBadge(for: Int(truncating: eventualBG))
                } else {
                    Text("---")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    Text("\(state.units.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .foregroundStyle(.primary)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.2))
            }
        }
    }

    @ViewBuilder private func eventualGlucoseBadge(for eventualBG: Int) -> some View {
        HStack {
            Text(
                state.units == .mgdL ? Decimal(eventualBG).description : eventualBG.formattedAsMmolL
            )
            .font(.footnote)
            .foregroundStyle(.primary)
            Text("\(state.units.rawValue)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var forecastChart: some View {
        Chart {
            drawGlucose()
            drawCurrentTimeMarker()

            if state.forecastDisplayType == .lines {
                drawForecastLines()
            } else {
                drawForecastsCone()
            }

            if let selectedGlucose {
                RuleMark(x: .value("Selection", selectedGlucose.date ?? Date.now, unit: .minute))
                    .foregroundStyle(Color.tabBar)
                    .lineStyle(.init(lineWidth: 2))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        selectionPopover
                    }

                PointMark(
                    x: .value("Time", selectedGlucose.date ?? Date.now, unit: .minute),
                    y: .value("Value", selectedGlucose.glucose)
                )
                .zIndex(-1)
                .symbolSize(CGSize(width: 15, height: 15))
                .foregroundStyle(
                    Decimal(selectedGlucose.glucose) > state.highGlucose ? Color.orange
                        .opacity(0.8) :
                        (
                            Decimal(selectedGlucose.glucose) < state.lowGlucose ? Color.red.opacity(0.8) : Color.green
                                .opacity(0.8)
                        )
                )

                PointMark(
                    x: .value("Time", selectedGlucose.date ?? Date.now, unit: .minute),
                    y: .value("Value", selectedGlucose.glucose)
                )
                .zIndex(-1)
                .symbolSize(CGSize(width: 6, height: 6))
                .foregroundStyle(Color.primary)
            }
        }
        .chartXSelection(value: $selection)
        .chartXAxis { forecastChartXAxis }
        .chartXScale(domain: startMarker ... endMarker)
        .chartYAxis { forecastChartYAxis }
        .chartYScale(domain: state.units == .mgdL ? 0 ... 300 : 0.asMmolL ... 300.asMmolL)
        .chartLegend {
            if state.forecastDisplayType == ForecastDisplayType.lines {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill").foregroundStyle(Color.insulin)
                        Text("IOB").foregroundStyle(Color.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill").foregroundStyle(Color.uam)
                        Text("UAM").foregroundStyle(Color.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill").foregroundStyle(Color.zt)
                        Text("ZT").foregroundStyle(Color.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill").foregroundStyle(Color.orange)
                        Text("COB").foregroundStyle(Color.secondary)
                    }
                }.font(.caption2)
            }
        }
        .chartForegroundStyleScale([
            "iob": Color.insulin,
            "uam": Color.uam,
            "zt": Color.zt,
            "cob": Color.orange
        ])
    }

    @ViewBuilder var selectionPopover: some View {
        if let sgv = selectedGlucose?.glucose {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "clock")
                    Text(selectedGlucose?.date?.formatted(.dateTime.hour().minute(.twoDigits)) ?? "")
                        .font(.footnote).bold()
                }.font(.footnote).padding(.bottom, 5)

                // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
                let hardCodedLow = Decimal(55)
                let hardCodedHigh = Decimal(220)
                let isDynamicColorScheme = state.glucoseColorScheme == .dynamicColor

                let glucoseColor = Trio.getDynamicGlucoseColor(
                    glucoseValue: Decimal(sgv),
                    highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : state.highGlucose,
                    lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : state.lowGlucose,
                    targetGlucose: state.currentBGTarget,
                    glucoseColorScheme: state.glucoseColorScheme
                )
                HStack {
                    Text(state.units == .mgdL ? Decimal(sgv).description : Decimal(sgv).formattedAsMmolL)
                        .bold()
                        + Text(" \(state.units.rawValue)")
                }.foregroundStyle(
                    Color(glucoseColor)
                ).font(.footnote)
            }
            .padding(7)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.chart.opacity(0.85))
                    .shadow(color: Color.secondary, radius: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary, lineWidth: 2)
                    )
            }
        }
    }

    private func drawGlucose() -> some ChartContent {
        ForEach(state.glucoseFromPersistence) { item in
            let glucoseToDisplay = state.units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL
            let targetGlucose = (state.determination.first?.currentTarget ?? state.currentBGTarget as NSDecimalNumber) as Decimal

            // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
            let hardCodedLow = Decimal(55)
            let hardCodedHigh = Decimal(220)
            let isDynamicColorScheme = state.glucoseColorScheme == .dynamicColor

            let pointMarkColor: Color = Trio.getDynamicGlucoseColor(
                glucoseValue: Decimal(item.glucose),
                highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : state.highGlucose,
                lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : state.lowGlucose,
                targetGlucose: targetGlucose,
                glucoseColorScheme: state.glucoseColorScheme
            )

            if !state.isSmoothingEnabled {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", glucoseToDisplay)
                )
                .foregroundStyle(pointMarkColor)
                .symbolSize(18)
            } else {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", glucoseToDisplay)
                )
                .symbol {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 6))
                        .bold()
                        .foregroundStyle(pointMarkColor)
                }
            }
        }
    }

    private func timeForIndex(_ index: Int32) -> Date {
        let currentTime = Date()
        let timeInterval = TimeInterval(index * 300)
        return currentTime.addingTimeInterval(timeInterval)
    }

    private func drawForecastsCone() -> some ChartContent {
        // Draw AreaMark for the forecast bounds
        ForEach(0 ..< max(state.minForecast.count, state.maxForecast.count), id: \.self) { index in
            if index < state.minForecast.count, index < state.maxForecast.count {
                let yMinMaxDelta = Decimal(state.minForecast[index] - state.maxForecast[index])
                let xValue = timeForIndex(Int32(index))

                // if distance between respective min and max is 0, provide a default range
                if yMinMaxDelta == 0 {
                    let yMinValue = state.units == .mgdL ? Decimal(state.minForecast[index] - 1) :
                        Decimal(state.minForecast[index] - 1)
                        .asMmolL
                    let yMaxValue = state.units == .mgdL ? Decimal(state.minForecast[index] + 1) :
                        Decimal(state.minForecast[index] + 1)
                        .asMmolL

                    AreaMark(
                        x: .value("Time", xValue <= endMarker ? xValue : endMarker),
                        yStart: .value("Min Value", state.units == .mgdL ? yMinValue : yMinValue.asMmolL),
                        yEnd: .value("Max Value", state.units == .mgdL ? yMaxValue : yMaxValue.asMmolL)
                    )
                    .foregroundStyle(Color.blue.opacity(0.5))
                    .interpolationMethod(.catmullRom)

                } else {
                    let yMinValue = Decimal(state.minForecast[index]) <= 300 ? Decimal(state.minForecast[index]) : Decimal(300)
                    let yMaxValue = Decimal(state.maxForecast[index]) <= 300 ? Decimal(state.maxForecast[index]) : Decimal(300)

                    AreaMark(
                        x: .value("Time", timeForIndex(Int32(index)) <= endMarker ? timeForIndex(Int32(index)) : endMarker),
                        yStart: .value("Min Value", state.units == .mgdL ? yMinValue : yMinValue.asMmolL),
                        yEnd: .value("Max Value", state.units == .mgdL ? yMaxValue : yMaxValue.asMmolL)
                    )
                    .foregroundStyle(Color.blue.opacity(0.5))
                    .interpolationMethod(.catmullRom)
                }
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
                        y: .value("Value", state.units == .mgdL ? Decimal(values[index]) : Decimal(values[index]).asMmolL)
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
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        }
    }

    private var forecastChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { _ in
            AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            AxisTick(length: 3, stroke: .init(lineWidth: 3)).foregroundStyle(Color.secondary)
            AxisValueLabel().font(.caption2).foregroundStyle(Color.secondary)
        }
    }
}
