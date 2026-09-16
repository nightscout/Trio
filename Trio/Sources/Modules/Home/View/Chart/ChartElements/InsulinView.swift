import Charts
import Foundation
import SwiftUI

/// `upstream/dev`'s bolus renderer, kept verbatim behind the developer switch so the two can
/// be compared on device — see `MainChartHelper.usesUpstreamTreatmentRenderingDefaultsKey`.
///
/// Everything `TreatmentOverlay` moved out is still here: the anchor lookup and the Core Data
/// reads run inside the chart content, once per marker per evaluation, and the triangle is an
/// `Image(systemName:)` — a SwiftUI view instantiated per data point. Deliberately not tidied.
struct LegacyInsulinView: ChartContent {
    let glucoseData: [GlucoseStored]
    let insulinData: [PumpEventStored]
    let units: GlucoseUnits
    let bolusDisplayThreshold: BolusDisplayThreshold

    var body: some ChartContent {
        drawBoluses()
    }

    private func drawBoluses() -> some ChartContent {
        ForEach(insulinData) { insulin in
            let amount = insulin.bolus?.amount ?? 0 as NSDecimalNumber
            let bolusDate = insulin.timestamp ?? Date()

            if amount != 0, let glucose = MainChartHelper.legacyTimeToNearestGlucose(
                glucoseValues: glucoseData,
                time: bolusDate.timeIntervalSince1970
            )?.glucose {
                let yPosition = (units == .mgdL ? Decimal(glucose) : Decimal(glucose).asMmolL) + MainChartHelper
                    .bolusOffset(units: units)
                let size = (MainChartHelper.Config.bolusSize + CGFloat(truncating: amount) * MainChartHelper.Config.bolusScale)

                PointMark(
                    x: .value("Time", bolusDate, unit: .second),
                    y: .value("Value", yPosition)
                )
                .symbol {
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: size)).foregroundStyle(Color.insulin)
                }

                PointMark(
                    x: .value("Time", bolusDate, unit: .second),
                    y: .value("Value", yPosition)
                )
                .symbolSize(0)
                .annotation(position: .top) {
                    if amount as Decimal >= bolusDisplayThreshold.rawValue {
                        Text(Formatter.bolusFormatter.string(from: amount) ?? "")
                            .font(.caption2)
                            .foregroundStyle(Color.primary)
                    }
                }
            }
        }
    }
}
