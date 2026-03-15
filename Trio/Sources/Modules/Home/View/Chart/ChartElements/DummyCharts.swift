import Charts
import Foundation
import SwiftUI

extension MainChartView {
    /// empty chart that just shows the Y axis and Y grid lines. Created separately from `mainChart` to allow main chart to scroll horizontally while having a fixed Y axis
    var staticYAxisChart: some View {
        Chart {
            /// high and low threshold lines

            // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
            let hardCodedLow = Decimal(55)
            let hardCodedHigh = Decimal(220)
            let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

            if thresholdLines {
                let highColor = Trio.getDynamicGlucoseColor(
                    glucoseValue: highGlucose,
                    highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                    lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                    targetGlucose: currentGlucoseTarget,
                    glucoseColorScheme: glucoseColorScheme
                )
                let lowColor = Trio.getDynamicGlucoseColor(
                    glucoseValue: lowGlucose,
                    highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                    lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                    targetGlucose: currentGlucoseTarget,
                    glucoseColorScheme: glucoseColorScheme
                )

                RuleMark(y: .value("High", units == .mgdL ? highGlucose : highGlucose.asMmolL))
                    .foregroundStyle(highColor)
                    .lineStyle(.init(lineWidth: 1, dash: [5]))
                RuleMark(y: .value("Low", units == .mgdL ? lowGlucose : lowGlucose.asMmolL))
                    .foregroundStyle(lowColor)
                    .lineStyle(.init(lineWidth: 1, dash: [5]))
            }
        }
        .id("DummyMainChart")
        .frame(
            minHeight: geo.size.height * (0.28 - safeAreaSize)
        )
        .frame(width: screenSize.width - 10)
        .chartXAxis { mainChartXAxis }
        .chartXScale(domain: state.startMarker ... state.endMarker)
        .chartXAxis(.hidden)
        .chartYAxis { mainChartYAxis }
        .chartYScale(
            domain: units == .mgdL ? state.minYAxisValue ... state.maxYAxisValue : state.minYAxisValue.asMmolL ... state
                .maxYAxisValue.asMmolL
        )
        .chartLegend(.hidden)
    }

    var dummyBasalChart: some View {
        Chart {}
            .id("DummyBasalChart")
            .frame(minHeight: geo.size.height * 0.05)
            .frame(width: screenSize.width - 10)
            .chartXAxis { basalChartXAxis }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
    }

    var dummyCobChart: some View {
        Chart {}
            .id("DummyCobChart")
            .frame(minHeight: geo.size.height * 0.12)
            .frame(width: screenSize.width - 10)
            .chartXScale(domain: state.startMarker ... state.endMarker)
            .chartXAxis { basalChartXAxis }
            .chartXAxis(.hidden)
            .chartYAxis { cobIobChartYAxis }
            .chartYAxis(.hidden)
            .chartYScale(domain: state.minValueCobChart ... state.maxValueCobChart)
            .chartLegend(.hidden)
    }
}
