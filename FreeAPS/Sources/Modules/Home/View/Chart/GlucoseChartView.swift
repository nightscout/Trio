import Charts
import Foundation
import SwiftUI

struct GlucoseChartView: ChartContent {
    let glucoseData: [GlucoseStored]
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let currentGlucoseTarget: Decimal
    let isSmoothingEnabled: Bool
    let glucoseColorStyle: GlucoseColorStyle

    var body: some ChartContent {
        drawGlucoseChart()
    }

    private func drawGlucoseChart() -> some ChartContent {
        ForEach(glucoseData) { item in
            let glucoseToDisplay = units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL

            let pointMarkColor = FreeAPS.getDynamicGlucoseColor(
                glucoseValue: glucoseToDisplay,
                highGlucoseColorValue: highGlucose,
                lowGlucoseColorValue: lowGlucose,
                targetGlucose: currentGlucoseTarget,
                glucoseColorStyle: glucoseColorStyle,
                offset: units == .mgdL ? 20 : 20.asMmolL
            )

            if !isSmoothingEnabled {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", glucoseToDisplay)
                )
                .foregroundStyle(pointMarkColor)
                .symbolSize(20)
                .symbol {
                    if item.isManual {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 10))
                            .symbolRenderingMode(.monochrome)
                            .bold()
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .bold()
                            .foregroundStyle(pointMarkColor)
                    }
                }
            } else {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", glucoseToDisplay)
                )
                .symbol {
                    if item.isManual {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 10))
                            .symbolRenderingMode(.monochrome)
                            .bold()
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 8))
                            .bold()
                            .foregroundStyle(pointMarkColor)
                    }
                }
            }
        }
    }
}
