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

        // Determine scale
        let minValue = min(additionalState.chart.min(by: { $0.value < $1.value })?.value ?? 39, 39)
        let maxValue = max(additionalState.chart.max(by: { $0.value < $1.value })?.value ?? maxThreshhold, maxThreshhold)

        let yAxisRuleMarkMin = isMgdL ? state.lowGlucose : state.lowGlucose
            .asMmolL
        let yAxisRuleMarkMax = isMgdL ? state.highGlucose : state.highGlucose
            .asMmolL
        let target = isMgdL ? state.target : state.target.asMmolL

        let isOverrideActive = additionalState.isOverrideActive == true

        let calendar = Calendar.current
        let now = Date()

        let startDate = calendar.date(byAdding: .hour, value: isWatchOS ? -3 : -6, to: now) ?? now
        let endDate = isOverrideActive ? (calendar.date(byAdding: .hour, value: 2, to: now) ?? now) :
            (calendar.date(byAdding: .minute, value: isWatchOS ? 5 : 0, to: now) ?? now)

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

        let end: Date = start.addingTimeInterval(durationAsTimeInterval)
        let target = context.state.detailedViewState.overrideTarget

        return RuleMark(
            xStart: .value("Start", start, unit: .second),
            xEnd: .value("End", end, unit: .second),
            y: .value("Value", target)
        )
        .foregroundStyle(Color.purple.opacity(0.6))
        .lineStyle(.init(lineWidth: 8))
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
