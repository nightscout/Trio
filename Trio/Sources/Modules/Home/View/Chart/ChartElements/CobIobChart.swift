import Charts
import Foundation
import SwiftUI

extension MainChartCanvas {
    var cobIobChart: some View {
        Chart {
            drawCurrentTimeMarker()
            drawCOBIOBChart()
        }
        .chartForegroundStyleScale([
            "COB": Color.orange,
            "IOB": Color.darkerBlue
        ])
        .chartLegend(.hidden)
        .frame(width: canvasWidth, height: cobIobHeight)
        .chartXScale(domain: state.startMarker ... state.endMarker)
        .chartXAxis { basalChartXAxis }
        .chartYAxis { cobIobChartYAxis }
        .chartYScale(domain: combinedYDomain())
    }

    func combinedYDomain() -> ClosedRange<Double> {
        MainChartHelper.cobIobYDomain(
            minCob: state.minValueCobChart,
            maxCob: state.maxValueCobChart,
            minIob: state.minValueIobChart,
            maxIob: state.maxValueIobChart
        )
    }

    func drawCOBIOBChart() -> some ChartContent {
        // Filter out duplicate entries by `deliverAt`,
        // We sometimes get two determinations when editing carbs, one without the entry-to-be-edited and then another one after editing the entry.
        // We are fetching determinations in descending order, so the first one is the latter determination (with correct amounts), so keeping the first one encountered.
        var seenDates = Set<Date>()
        let filteredDeterminations = state.enactedAndNonEnactedDeterminations.filter { item in
            if let date = item.deliverAt {
                if seenDates.contains(date) {
                    // Already seen this date – filter it out.
                    return false
                } else {
                    seenDates.insert(date)
                    return true
                }
            }
            return true
        }

        return ForEach(filteredDeterminations) { item in

            // MARK: - COB line and area mark

            let amountCOB = Int(item.cob)
            let date: Date = item.deliverAt ?? Date()

            LineMark(x: .value("Time", date), y: .value("Value", amountCOB))
                .foregroundStyle(by: .value("Type", "COB"))
                .position(by: .value("Axis", "COB"))
            AreaMark(x: .value("Time", date), y: .value("Value", amountCOB))
                .foregroundStyle(by: .value("Type", "COB"))
                .position(by: .value("Axis", "COB"))
                .opacity(0.2)

            // MARK: - IOB line and area mark

            let rawAmount = item.iob?.doubleValue ?? 0
            let amountIOB: Double = MainChartHelper.scaledIobAmount(rawAmount)

            AreaMark(x: .value("Time", date), y: .value("Amount", amountIOB))
                .foregroundStyle(by: .value("Type", "IOB"))
                .position(by: .value("Axis", "IOB"))
                .opacity(0.2)
            LineMark(x: .value("Time", date), y: .value("Amount", amountIOB))
                .foregroundStyle(by: .value("Type", "IOB"))
                .position(by: .value("Axis", "IOB"))
        }
    }
}
