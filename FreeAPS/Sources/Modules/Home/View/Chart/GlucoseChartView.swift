import Charts
import Foundation
import SwiftUI

struct GlucoseChartView: ChartContent {
    let glucoseData: [GlucoseStored]
    let manualGlucoseData: [GlucoseStored]
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let smooth: Bool
    let gradientStops: [Gradient.Stop]

    var body: some ChartContent {
        drawGlucoseChart()
    }

    private func drawGlucoseChart() -> some ChartContent {
        ForEach(glucoseData) { item in
            let glucoseToDisplay = units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL

            if smooth {
                LineMark(x: .value("Time", item.date ?? Date()), y: .value("Value", glucoseToDisplay))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(stops: gradientStops),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .symbol(.circle)
                    .symbolSize(34)
            } else {
                if glucoseToDisplay > highGlucose {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", glucoseToDisplay)
                    ).foregroundStyle(Color.orange.gradient).symbolSize(20)
                } else if glucoseToDisplay < lowGlucose {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", glucoseToDisplay)
                    ).foregroundStyle(Color.red.gradient).symbolSize(20)
                } else {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", glucoseToDisplay)
                    ).foregroundStyle(Color.green.gradient).symbolSize(20)
                }
            }
        }
    }
}
