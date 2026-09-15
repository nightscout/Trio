import Charts
import Foundation
import SwiftUI

struct InsulinView: ChartContent {
    let glucoseData: [GlucoseStored]
    let insulinData: [PumpEventStored]
    let units: GlucoseUnits
    let bolusDisplayThreshold: BolusDisplayThreshold
    /// Events whose amount label is far enough from its neighbours' to be readable. A label is
    /// several times wider than the marker it belongs to, so in a dense stretch most of them
    /// would land on top of each other — and each one costs a laid-out SwiftUI view whether it
    /// can be read or not. Empty means "label everything", which is what a caller that does not
    /// thin gets.
    var labelledEventIDs: Set<String> = []

    var body: some ChartContent {
        drawBoluses()
    }

    private func showsLabel(_ insulin: PumpEventStored) -> Bool {
        guard !labelledEventIDs.isEmpty else { return true }
        return insulin.id.map(labelledEventIDs.contains) ?? false
    }

    private func drawBoluses() -> some ChartContent {
        ForEach(insulinData) { insulin in
            let amount = insulin.bolus?.amount ?? 0 as NSDecimalNumber
            let bolusDate = insulin.timestamp ?? Date()

            if amount != 0, let glucose = MainChartHelper.timeToNearestGlucose(
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

                if amount as Decimal >= bolusDisplayThreshold.rawValue, showsLabel(insulin) {
                    PointMark(
                        x: .value("Time", bolusDate, unit: .second),
                        y: .value("Value", yPosition)
                    )
                    .symbolSize(0)
                    .annotation(position: .top) {
                        Text(Formatter.bolusFormatter.string(from: amount) ?? "")
                            .font(.caption2)
                            .foregroundStyle(Color.primary)
                    }
                }
            }
        }
    }
}
