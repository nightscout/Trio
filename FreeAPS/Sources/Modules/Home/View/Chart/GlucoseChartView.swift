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

            // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
            let hardCodedLow = Decimal(55)
            let hardCodedHigh = Decimal(220)
            let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

            let pointMarkColor: Color = FreeAPS.getDynamicGlucoseColor(
                glucoseValue: Decimal(item.glucose),
                highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                targetGlucose: currentGlucoseTarget,
                glucoseColorScheme: glucoseColorScheme
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
