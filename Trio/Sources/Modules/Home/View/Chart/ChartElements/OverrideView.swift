import Charts
import CoreData
import Foundation
import SwiftUI

struct OverrideView: ChartContent {
    var state: Home.StateModel
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
            let start: Date = override.date ?? .distantPast
            let duration = MainChartHelper.calculateDuration(
                objectID: override.objectID,
                attribute: "duration",
                context: viewContext
            ) ?? 0
            let end: Date = {
                if override.indefinite {
                    return start.addingTimeInterval(60 * 60 * 24 * 30)
                } else if duration != 0 {
                    return start.addingTimeInterval(duration)
                } else {
                    return start.addingTimeInterval(60 * 60 * 24 * 30)
                }
            }()

            let target = getOverrideTarget(override: override)

            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", units == .mgdL ? target : target.asMmolL)
            )
            .foregroundStyle(Color.purple.opacity(0.4))
            .lineStyle(.init(lineWidth: 8))
        }
    }

    private func drawOverrideRunStored() -> some ChartContent {
        ForEach(overrideRunStored) { overrideRunStored in
            let start: Date = overrideRunStored.startDate ?? .distantPast
            let end: Date = overrideRunStored.endDate ?? Date()
            let target = (overrideRunStored.target?.decimalValue ?? 100) == 0 ? 100 : overrideRunStored.target!.decimalValue
            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", units == .mgdL ? target : target.asMmolL)
            )
            .foregroundStyle(Color.purple.opacity(0.25))
            .lineStyle(.init(lineWidth: 8))
        }
    }

    // Handle Overrides where no Target is provided
    private func getOverrideTarget(override: OverrideStored) -> Decimal {
        if let target = MainChartHelper
            .calculateTarget(objectID: override.objectID, attribute: "target", context: viewContext)
        {
            return target
        } else if override.target == 0 {
            return state.currentGlucoseTarget // Default target
        } else {
            return override.target?.decimalValue ?? state.currentGlucoseTarget
        }
    }
}
