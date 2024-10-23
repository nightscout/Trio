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
        .chartYScale(domain: state.minValueCobChart ... state.maxValueCobChart)
    }

    func drawCOB(dummy: Bool) -> some ChartContent {
        ForEach(state.enactedAndNonEnactedDeterminations) { cob in
            let amount = Int(cob.cob)
            let date: Date = cob.deliverAt ?? Date()

            if dummy {
                LineMark(x: .value("Time", date), y: .value("Value", amount))
                    .foregroundStyle(Color.clear)
                AreaMark(x: .value("Time", date), y: .value("Value", amount)).foregroundStyle(
                    Color.clear
                )
            } else {
                LineMark(x: .value("Time", date), y: .value("Value", amount))
                    .foregroundStyle(Color.orange.gradient)
                AreaMark(x: .value("Time", date), y: .value("Value", amount)).foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(
                            colors: [
                                Color.orange.opacity(0.8),
                                Color.orange.opacity(0.01)
                            ]
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}
