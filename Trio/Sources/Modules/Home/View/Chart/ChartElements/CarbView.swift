import Charts
import Foundation
import SwiftUI

struct CarbView: ChartContent {
    let glucoseData: [GlucoseStored]
    let units: GlucoseUnits
    let carbData: [CarbEntryStored]
    let fpuData: [CarbEntryStored]
    let minValue: Decimal

    var body: some ChartContent {
        drawCarbs()
        drawFpus()
    }

    private func drawCarbs() -> some ChartContent {
        ForEach(carbData) { carb in
            let carbAmount = carb.carbs
            let carbDate = carb.date ?? Date()

            if let glucose = MainChartHelper.timeToNearestGlucose(
                glucoseValues: glucoseData,
                time: carbDate.timeIntervalSince1970
            )?.glucose {
                let yPosition = (units == .mgdL ? Decimal(glucose) : Decimal(glucose).asMmolL) - MainChartHelper
                    .bolusOffset(units: units)
                let size = min(
                    MainChartHelper.Config.carbsSize + CGFloat(carbAmount) * MainChartHelper.Config.carbsScale,
                    MainChartHelper.Config.maxCarbSize
                )

                PointMark(
                    x: .value("Time", carbDate, unit: .second),
                    y: .value("Value", yPosition)
                )
                .symbol {
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: size)).foregroundStyle(Color.orange)
                        .rotationEffect(.degrees(180))
                }
                .annotation(position: .bottom) {
                    Text(Formatter.integerFormatter.string(from: carbAmount as NSNumber)!).font(.caption2)
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }

    private func drawFpus() -> some ChartContent {
        ForEach(fpuData, id: \.id) { fpu in
            let fpuAmount = fpu.carbs
            let size = (MainChartHelper.Config.fpuSize + CGFloat(fpuAmount) * MainChartHelper.Config.carbsScale) * 1.8
            let yPosition = minValue // value is parsed to mmol/L when passed into struct based on user settings

            PointMark(
                x: .value("Time", fpu.date ?? Date(), unit: .second),
                y: .value("Value", yPosition)
            )
            .symbolSize(size)
            .foregroundStyle(Color.brown)
        }
    }
}
