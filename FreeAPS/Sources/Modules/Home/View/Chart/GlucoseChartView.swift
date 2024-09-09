import Charts
import Foundation
import SwiftUI

struct GlucoseChartView: ChartContent {
    let glucoseData: [GlucoseStored]
    let manualGlucoseData: [GlucoseStored]
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let isSmoothingEnabled: Bool

    var body: some ChartContent {
        drawGlucoseChart()
    }

    private func drawGlucoseChart() -> some ChartContent {
        ForEach(glucoseData) { item in
            let glucoseToDisplay = units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL
            let pointMarkColor: Color = glucoseToDisplay > highGlucose ? Color.orange :
                glucoseToDisplay < lowGlucose ? Color.red :
                Color.green

            if !isSmoothingEnabled {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", glucoseToDisplay)
                )
                .foregroundStyle(pointMarkColor)
                .symbolSize(20)
            } else {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", glucoseToDisplay)
                )
                .symbol {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 8))
                        .bold()
                        .foregroundStyle(pointMarkColor)
                }
            }
        }
    }
}
