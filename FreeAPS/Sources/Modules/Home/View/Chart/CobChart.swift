import Charts
import Foundation
import SwiftUI

extension MainChartView {
    var cobChart: some View {
        Chart {
            drawCurrentTimeMarker()
            drawCOB(dummy: false)

            if #available(iOS 17, *) {
                if let selectedCOBValue {
                    PointMark(
                        x: .value("Time", selectedCOBValue.deliverAt ?? now, unit: .minute),
                        y: .value("Value", selectedCOBValue.cob)
                    )
                    .symbolSize(CGSize(width: 15, height: 15))
                    .foregroundStyle(Color.orange.opacity(0.8))

                    PointMark(
                        x: .value("Time", selectedCOBValue.deliverAt ?? now, unit: .minute),
                        y: .value("Value", selectedCOBValue.cob)
                    )
                    .symbolSize(CGSize(width: 6, height: 6))
                    .foregroundStyle(Color.primary)
                }
            }
        }
        .frame(minHeight: geo.size.height * 0.12)
        .frame(width: fullWidth(viewWidth: screenSize.width))
        .chartXScale(domain: startMarker ... endMarker)
        .backport.chartXSelection(value: $selection)
        .chartXAxis { basalChartXAxis }
        .chartYAxis { cobChartYAxis }
        .chartYScale(domain: minValueCobChart ... maxValueCobChart)
    }
}
