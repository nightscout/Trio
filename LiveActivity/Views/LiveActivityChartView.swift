//
//  LiveActivityChartView.swift
//  Trio
//
//  Created by Cengiz Deniz on 17.10.24.
//
import Charts
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityChartView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isWatchOS) var isWatchOS

    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState

    var body: some View {
        let state = context.state
        let isMgdL: Bool = state.unit == "mg/dL"

        let maxThreshhold: Decimal = isWatchOS ? 220 : 300

        // Determine scale, accounting for both glucose history and prediction values
        let chartMin = additionalState.chart.min(by: { $0.value < $1.value })?.value ?? 39
        let chartMax = additionalState.chart.max(by: { $0.value < $1.value })?.value ?? maxThreshhold
        let forecastMin = additionalState.minForecast.min().map { Decimal($0) } ?? chartMin
        let forecastMax = additionalState.maxForecast.max().map { Decimal($0) } ?? chartMax
        let minValue = min(min(chartMin, forecastMin), 39)
        let maxValue = max(max(chartMax, forecastMax), maxThreshhold)

        let yAxisRuleMarkMin = isMgdL ? state.lowGlucose : state.lowGlucose
            .asMmolL
        let yAxisRuleMarkMax = isMgdL ? state.highGlucose : state.highGlucose
            .asMmolL
        let target = isMgdL ? state.target : state.target.asMmolL

        let isOverrideActive = additionalState.isOverrideActive == true
        let isTempTargetActive = additionalState.isTempTargetActive == true
        let hasForecast = !additionalState.minForecast.isEmpty || !additionalState.forecastLines.isEmpty

        let calendar = Calendar.current
        let now = Date()

        let startDate = calendar.date(byAdding: .hour, value: isWatchOS ? -3 : -6, to: now) ?? now
        let endDate: Date = {
            let baseEnd = calendar.date(byAdding: .minute, value: isWatchOS ? 5 : 0, to: now) ?? now
            guard hasForecast, let anchorDate = state.date else { return baseEnd }
            let forecastCount = max(
                additionalState.minForecast.count,
                additionalState.forecastLines.max(by: { $0.values.count < $1.values.count })?.values.count ?? 0
            )
            let predictionEnd = anchorDate.addingTimeInterval(TimeInterval(forecastCount * 300))
            return max(baseEnd, predictionEnd)
        }()

        // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
        let hardCodedLow = isMgdL ? Decimal(55) : 55.asMmolL
        let hardCodedHigh = isMgdL ? Decimal(220) : 220.asMmolL
        let hasStaticColorScheme = context.state.glucoseColorScheme == "staticColor"

        let highColor = Color.getDynamicGlucoseColor(
            glucoseValue: yAxisRuleMarkMax,
            highGlucoseColorValue: !hasStaticColorScheme ? hardCodedHigh : yAxisRuleMarkMax,
            lowGlucoseColorValue: !hasStaticColorScheme ? hardCodedLow : yAxisRuleMarkMin,
            targetGlucose: target,
            glucoseColorScheme: context.state.glucoseColorScheme
        )

        let lowColor = Color.getDynamicGlucoseColor(
            glucoseValue: yAxisRuleMarkMin,
            highGlucoseColorValue: !hasStaticColorScheme ? hardCodedHigh : yAxisRuleMarkMax,
            lowGlucoseColorValue: !hasStaticColorScheme ? hardCodedLow : yAxisRuleMarkMin,
            targetGlucose: target,
            glucoseColorScheme: context.state.glucoseColorScheme
        )

        Chart {
            RuleMark(y: .value("High", yAxisRuleMarkMax))
                .foregroundStyle(highColor)
                .lineStyle(.init(lineWidth: 1, dash: [5]))

            RuleMark(y: .value("Low", yAxisRuleMarkMin))
                .foregroundStyle(lowColor)
                .lineStyle(.init(lineWidth: 1, dash: [5]))

            RuleMark(y: .value("Target", target))
                .foregroundStyle(.green.gradient)
                .lineStyle(.init(lineWidth: 1.5))

            if isOverrideActive {
                drawActiveOverrides()
            }

            if isTempTargetActive {
                drawActiveTempTarget()
            }

            if hasForecast, let anchorDate = state.date {
                if additionalState.forecastDisplayType == "lines" {
                    drawForecastLines(anchorDate: anchorDate, isMgdL: isMgdL)
                } else {
                    drawForecastCone(anchorDate: anchorDate, isMgdL: isMgdL, maxValue: maxValue)
                }
            }

            drawChart(yAxisRuleMarkMin: yAxisRuleMarkMin, yAxisRuleMarkMax: yAxisRuleMarkMax)
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine(stroke: .init(lineWidth: 0.65, dash: [2, 3]))
                    .foregroundStyle(Color.white.opacity(colorScheme == .light ? 1 : 0.5))
                AxisValueLabel().foregroundStyle(.primary).font(.footnote)
            }
        }
        .chartYScale(domain: state.unit == "mg/dL" ? minValue ... maxValue : minValue.asMmolL ... maxValue.asMmolL)
        .chartYAxis(.hidden)
        .chartPlotStyle { plotContent in
            plotContent
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .light ? Color.black.opacity(0.2) : .clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .chartXScale(domain: startDate ... endDate)
        .chartXAxis {
            AxisMarks(position: .automatic) { _ in
                AxisGridLine(stroke: .init(lineWidth: 0.65, dash: [2, 3]))
                    .foregroundStyle(Color.primary.opacity(colorScheme == .light ? 1 : 0.5))
            }
        }
    }

    private func drawActiveOverrides() -> some ChartContent {
        let start: Date = context.state.detailedViewState.overrideDate

        let duration = context.state.detailedViewState.overrideDuration
        let durationAsTimeInterval = TimeInterval((duration as NSDecimalNumber).doubleValue * 60) // return seconds

        let end: Date = duration == 0
            ? Date(timeIntervalSinceNow: 7200)
            : start.addingTimeInterval(durationAsTimeInterval)
        let target = context.state.detailedViewState.overrideTarget

        return RuleMark(
            xStart: .value("Start", start, unit: .second),
            xEnd: .value("End", end, unit: .second),
            y: .value("Value", target)
        )
        .foregroundStyle(Color.purple.opacity(0.6))
        .lineStyle(.init(lineWidth: 8))
    }

    private func drawActiveTempTarget() -> some ChartContent {
        let start: Date = context.state.detailedViewState.tempTargetDate

        let duration = context.state.detailedViewState.tempTargetDuration
        let durationAsTimeInterval = TimeInterval((duration as NSDecimalNumber).doubleValue * 60) // return seconds

        let end: Date = start.addingTimeInterval(durationAsTimeInterval)
        let target = context.state.detailedViewState.tempTargetTarget

        return RuleMark(
            xStart: .value("Start", start, unit: .second),
            xEnd: .value("End", end, unit: .second),
            y: .value("Value", target)
        )
        .foregroundStyle(Color("LoopGreen").opacity(0.6))
        .lineStyle(.init(lineWidth: 8))
    }

    private func timeForIndex(_ index: Int, anchorDate: Date) -> Date {
        anchorDate.addingTimeInterval(TimeInterval(index * 300))
    }

    private func drawForecastCone(anchorDate: Date, isMgdL: Bool, maxValue: Decimal) -> some ChartContent {
        let minForecast = additionalState.minForecast
        let maxForecast = additionalState.maxForecast
        let cappedMax = isMgdL ? maxValue : maxValue.asMmolL
        let count = min(minForecast.count, maxForecast.count)

        // Pre-compute cone data to avoid conditionals inside the ForEach closure
        let coneData: [(date: Date, yMin: Decimal, yMax: Decimal)] = (0 ..< count).map { index in
            let xValue = timeForIndex(index, anchorDate: anchorDate)
            let delta = minForecast[index] - maxForecast[index]
            let yMin: Decimal
            let yMax: Decimal
            if delta == 0 {
                let base = isMgdL ? Decimal(minForecast[index]) : Decimal(minForecast[index]).asMmolL
                yMin = base - 1
                yMax = base + 1
            } else {
                yMin = isMgdL ? Decimal(minForecast[index]) : Decimal(minForecast[index]).asMmolL
                yMax = isMgdL ? Decimal(maxForecast[index]) : Decimal(maxForecast[index]).asMmolL
            }
            return (date: xValue, yMin: min(yMin, cappedMax), yMax: min(yMax, cappedMax))
        }

        return ForEach(coneData.indices, id: \.self) { i in
            AreaMark(
                x: .value("Time", coneData[i].date),
                yStart: .value("Min", coneData[i].yMin),
                yEnd: .value("Max", coneData[i].yMax)
            )
            .foregroundStyle(Color.blue.opacity(0.5))
            .interpolationMethod(.linear)
        }
    }

    private func drawForecastLines(anchorDate: Date, isMgdL: Bool) -> some ChartContent {
        let colorMap: [String: Color] = [
            "iob": Color(red: 0.118, green: 0.588, blue: 0.988),
            "cob": Color.orange,
            "uam": Color(red: 0.820, green: 0.169, blue: 0.969),
            "zt": Color(red: 0.443, green: 0.380, blue: 0.937)
        ]

        let points: [(series: String, date: Date, value: Decimal)] = additionalState.forecastLines.flatMap { line in
            line.values.enumerated().map { index, value in
                let displayValue = isMgdL ? Decimal(value) : Decimal(value).asMmolL
                return (series: line.type, date: timeForIndex(index, anchorDate: anchorDate), value: displayValue)
            }
        }

        return ForEach(Array(points.indices), id: \.self) { i in
            let point = points[i]
            LineMark(
                x: .value("Time", point.date),
                y: .value("Value", point.value),
                series: .value("Type", point.series)
            )
            .foregroundStyle(colorMap[point.series] ?? Color.gray)
            .lineStyle(.init(lineWidth: 1.5))
            .interpolationMethod(.linear)
        }
    }

    private func drawChart(yAxisRuleMarkMin _: Decimal, yAxisRuleMarkMax _: Decimal) -> some ChartContent {
        // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
        let hardCodedLow = Decimal(55)
        let hardCodedHigh = Decimal(220)
        let hasStaticColorScheme = context.state.glucoseColorScheme == "staticColor"
        let isMgdL = context.state.unit == "mg/dL"

        let threeHours = TimeInterval(10800)
        let chartData = isWatchOS ? additionalState.chart
            .filter { abs($0.date.timeIntervalSinceNow) < threeHours } : additionalState
            .chart

        return ForEach(chartData, id: \.self) { item in
            let displayValue = isMgdL ? item.value : item.value.asMmolL

            let pointMarkColor = Color.getDynamicGlucoseColor(
                glucoseValue: item.value,
                highGlucoseColorValue: !hasStaticColorScheme ? hardCodedHigh : context.state.highGlucose,
                lowGlucoseColorValue: !hasStaticColorScheme ? hardCodedLow : context.state.lowGlucose,
                targetGlucose: context.state.target,
                glucoseColorScheme: context.state.glucoseColorScheme
            )

            let pointMark = PointMark(
                x: .value("Time", item.date),
                y: .value("Value", displayValue)
            )
            .symbolSize(16)
            .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 0)

            pointMark.foregroundStyle(pointMarkColor)
        }
    }
}
