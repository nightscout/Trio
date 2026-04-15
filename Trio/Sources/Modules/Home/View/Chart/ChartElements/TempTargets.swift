import Charts
import CoreData
import Foundation
import SwiftUI

struct TempTargetView: ChartContent {
    let tempTargetStored: [TempTargetStored]
    let tempTargetRunStored: [TempTargetRunStored]
    let units: GlucoseUnits
    let viewContext: NSManagedObjectContext

    var body: some ChartContent {
        drawActiveTempTargets()
        drawTempTargetRunStored()
    }

    private func drawActiveTempTargets() -> some ChartContent {
        ForEach(tempTargetStored) { tt in
            if let duration = MainChartHelper.calculateDuration(
                objectID: tt.objectID,
                attribute: "duration",
                context: viewContext
            ) {
                let start: Date = tt.date ?? .distantPast
                let end: Date = start.addingTimeInterval(duration)

                if let target = MainChartHelper
                    .calculateTarget(objectID: tt.objectID, attribute: "target", context: viewContext)
                {
                    RuleMark(
                        xStart: .value("Start", start, unit: .second),
                        xEnd: .value("End", end, unit: .second),
                        y: .value("Value", units == .mgdL ? target : target.asMmolL)
                    )
                    .foregroundStyle(Color.green.opacity(0.4))
                    .lineStyle(.init(lineWidth: 8))
                }
            }
        }
    }

    private func drawTempTargetRunStored() -> some ChartContent {
        ForEach(tempTargetRunStored) { tt in
            let start: Date = tt.startDate ?? .distantPast
            let end: Date = tt.endDate ?? Date()
            let target = tt.target?.decimalValue ?? 100
            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", units == .mgdL ? target : target.asMmolL)
            )
            .foregroundStyle(Color.green.opacity(0.25))
            .lineStyle(.init(lineWidth: 8))
        }
    }
}
