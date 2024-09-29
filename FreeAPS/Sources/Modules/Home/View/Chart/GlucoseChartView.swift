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
    let glucoseColorScheme: GlucoseColorScheme

    var body: some ChartContent {
        drawGlucoseChart()
    }

    private func drawGlucoseChart() -> some ChartContent {
        ForEach(glucoseData) { item in
            let glucoseToDisplay = units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL

            // low glucose and high glucose is parsed in state to mmol/L; parse it back to mg/dL here for comparison
            let lowGlucose = units == .mgdL ? lowGlucose : lowGlucose.asMgdL
            let highGlucose = units == .mgdL ? highGlucose : highGlucose.asMgdL

            let pointMarkColor: Color = FreeAPS.getDynamicGlucoseColor(
                glucoseValue: Decimal(item.glucose),
                highGlucoseColorValue: highGlucose,
                lowGlucoseColorValue: lowGlucose,
                targetGlucose: currentGlucoseTarget,
                glucoseColorScheme: glucoseColorScheme,
                offset: 20
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
