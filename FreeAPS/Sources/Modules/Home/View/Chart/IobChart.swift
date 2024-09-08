import Charts
import Foundation
import SwiftUI

extension MainChartView {
    var iobChart: some View {
        VStack {
            Chart {
                drawIOB()

                if #available(iOS 17, *) {
                    if let selectedIOBValue {
                        PointMark(
                            x: .value("Time", selectedIOBValue.deliverAt ?? now, unit: .minute),
                            y: .value("Value", Int(truncating: selectedIOBValue.iob ?? 0))
                        )
                        .symbolSize(CGSize(width: 15, height: 15))
                        .foregroundStyle(Color.darkerBlue.opacity(0.8))

                        PointMark(
                            x: .value("Time", selectedIOBValue.deliverAt ?? now, unit: .minute),
                            y: .value("Value", Int(truncating: selectedIOBValue.iob ?? 0))
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
            .chartYScale(domain: minValueIobChart ... maxValueIobChart)
            .chartYAxis(.hidden)
        }
    }
}
