import Charts
import CoreData
import Foundation
import SwiftUI

struct OverrideView: ChartContent {
    let overrides: [OverrideStored]
    let overrideRunStored: [OverrideRunStored]
    let units: GlucoseUnits
    let viewContext: NSManagedObjectContext

    var body: some ChartContent {
        drawActiveOverrides()
        drawOverrideRunStored()
    }

    private func drawActiveOverrides() -> some ChartContent {
        ForEach(overrides) { override in
            if let duration = MainChartHelper.calculateDuration(objectID: override.objectID, context: viewContext) {
                let start: Date = override.date ?? .distantPast
                let end: Date = start.addingTimeInterval(duration)

                if let target = MainChartHelper.calculateTarget(objectID: override.objectID, context: viewContext) {
                    RuleMark(
                        xStart: .value("Start", start, unit: .second),
                        xEnd: .value("End", end, unit: .second),
                        y: .value("Value", units == .mgdL ? target : target.asMmolL)
                    )
                    .foregroundStyle(Color.purple.opacity(0.4))
                    .lineStyle(.init(lineWidth: 8))
                }
            }
        }
    }

    private func drawOverrideRunStored() -> some ChartContent {
        ForEach(overrideRunStored) { overrideRunStored in
            let start: Date = overrideRunStored.startDate ?? .distantPast
            let end: Date = overrideRunStored.endDate ?? Date()
            let target = overrideRunStored.target?.decimalValue ?? 100
            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", units == .mgdL ? target : target.asMmolL)
            )
            .foregroundStyle(Color.purple.opacity(0.25))
            .lineStyle(.init(lineWidth: 8))
        }
    }
}
