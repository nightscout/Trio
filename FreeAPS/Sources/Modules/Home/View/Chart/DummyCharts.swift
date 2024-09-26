import Charts
import Foundation
import SwiftUI

extension MainChartView {
    /// empty chart that just shows the Y axis and Y grid lines. Created separately from `mainChart` to allow main chart to scroll horizontally while having a fixed Y axis
    var staticYAxisChart: some View {
        Chart {
            /// high and low threshold lines
            if thresholdLines {
                RuleMark(y: .value("High", highGlucose)).foregroundStyle(Color.loopYellow)
                    .lineStyle(.init(lineWidth: 1, dash: [5]))
                RuleMark(y: .value("Low", lowGlucose)).foregroundStyle(Color.loopRed)
                    .lineStyle(.init(lineWidth: 1, dash: [5]))
            }
        }
        .id("DummyMainChart")
        .frame(minHeight: geo.size.height * 0.28)
        .frame(width: screenSize.width - 10)
        .chartXAxis { mainChartXAxis }
        .chartXScale(domain: startMarker ... endMarker)
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
        Chart {
            drawCOB(dummy: true)
        }
        .id("DummyCobChart")
        .frame(minHeight: geo.size.height * 0.12)
        .frame(width: screenSize.width - 10)
        .chartXScale(domain: startMarker ... endMarker)
        .chartXAxis { basalChartXAxis }
        .chartXAxis(.hidden)
        .chartYAxis { cobChartYAxis }
        .chartYAxis(.hidden)
        .chartYScale(domain: state.minValueCobChart ... state.maxValueCobChart)
        .chartLegend(.hidden)
    }
}
