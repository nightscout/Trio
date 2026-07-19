import Charts
import Foundation
import SwiftUI

extension MainChartView {
    /// empty chart that just shows the Y axis and Y grid lines. Created separately from `mainChart` to allow main chart to scroll horizontally while having a fixed Y axis
    var staticYAxisChart: some View {
        Chart {}
            .id("DummyMainChart")
            .frame(
                minHeight: mainHeight
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
            .frame(minHeight: basalHeight)
            .frame(width: screenSize.width - 10)
            .chartXAxis { basalChartXAxis }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
    }

    var dummyCobChart: some View {
        Chart {}
            .id("DummyCobChart")
            .frame(minHeight: cobIobHeight)
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
