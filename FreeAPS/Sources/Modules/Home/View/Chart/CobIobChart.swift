import Charts
import Foundation
import SwiftUI

extension MainChartView {
    var cobIobChart: some View {
        Chart {
            drawCurrentTimeMarker()
            drawIOB()
            drawCOB(dummy: false)

            if let selectedCOBValue {
                PointMark(
                    x: .value("Time", selectedCOBValue.deliverAt ?? now, unit: .minute),
                    y: .value("Value", selectedCOBValue.cob)
                )
                .symbolSize(CGSize(width: 15, height: 15))
                .foregroundStyle(Color.orange.opacity(0.8))
                .position(by: .value("Axis", "COB"))

                PointMark(
                    x: .value("Time", selectedCOBValue.deliverAt ?? now, unit: .minute),
                    y: .value("Value", selectedCOBValue.cob)
                )
                .symbolSize(CGSize(width: 6, height: 6))
                .foregroundStyle(Color.primary)
                .position(by: .value("Axis", "COB"))
            }

            if let selectedIOBValue {
                PointMark(
                    x: .value("Time", selectedIOBValue.deliverAt ?? now, unit: .minute),
                    y: .value("Value", Int(truncating: selectedIOBValue.iob ?? 0))
                )
                .symbolSize(CGSize(width: 15, height: 15))
                .foregroundStyle(Color.darkerBlue.opacity(0.8))
                .position(by: .value("Axis", "IOB"))

                PointMark(
                    x: .value("Time", selectedIOBValue.deliverAt ?? now, unit: .minute),
                    y: .value("Value", Int(truncating: selectedIOBValue.iob ?? 0))
                )
                .symbolSize(CGSize(width: 6, height: 6))
                .foregroundStyle(Color.primary)
                .position(by: .value("Axis", "IOB"))
            }
        }
        .chartForegroundStyleScale([
            "COB": Color.orange,
            "IOB": Color.darkerBlue
        ])
        .chartLegend(.hidden)
        .frame(minHeight: geo.size.height * 0.12)
        .frame(width: fullWidth(viewWidth: screenSize.width))
        .chartXScale(domain: startMarker ... endMarker)
        .backport.chartXSelection(value: $selection)
        .chartXAxis { basalChartXAxis }
        .chartYAxis { cobIobChartYAxis }
        .chartYScale(domain: combinedYDomain())
    }

    func combinedYDomain() -> ClosedRange<Double> {
        let minValue = min(state.minValueCobChart, state.minValueIobChart)
        let maxValue = max(state.maxValueCobChart, state.maxValueIobChart)
        return Double(minValue) ... Double(maxValue)
    }

    func drawCOB(dummy: Bool) -> some ChartContent {
        ForEach(state.enactedAndNonEnactedDeterminations) { cob in
            let amount = Int(cob.cob)
            let date: Date = cob.deliverAt ?? Date()

            if dummy {
                LineMark(x: .value("Time", date), y: .value("Value", amount))
                    .foregroundStyle(Color.clear)
                    .position(by: .value("Axis", "COB"))
                AreaMark(x: .value("Time", date), y: .value("Value", amount))
                    .foregroundStyle(Color.clear)
                    .position(by: .value("Axis", "COB"))
            } else {
                LineMark(x: .value("Time", date), y: .value("Value", amount))
                    .foregroundStyle(by: .value("Type", "COB"))
                    .position(by: .value("Axis", "COB"))
                AreaMark(x: .value("Time", date), y: .value("Value", amount))
                    .foregroundStyle(by: .value("Type", "COB"))
                    .position(by: .value("Axis", "COB"))
                    .opacity(0.2)
            }
        }
    }

    func drawIOB() -> some ChartContent {
        ForEach(state.enactedAndNonEnactedDeterminations) { iob in
            let rawAmount = iob.iob?.doubleValue ?? 0

            // as iob and cob share the same y axis and cob is usually >> iob we need to weigh iob visually
            let amount: Double = rawAmount > 0 ? rawAmount * 3 : rawAmount * 4
            let date: Date = iob.deliverAt ?? Date()

            AreaMark(x: .value("Time", date), y: .value("Amount", amount))
                .foregroundStyle(by: .value("Type", "IOB"))
                .position(by: .value("Axis", "IOB"))
                .opacity(0.2)
            LineMark(x: .value("Time", date), y: .value("Amount", amount))
                .foregroundStyle(by: .value("Type", "IOB"))
                .position(by: .value("Axis", "IOB"))
        }
    }
}
