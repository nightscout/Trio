import Charts
import CoreData
import Foundation
import SwiftUI

struct PhysioTestOverlayView: ChartContent {
    let activeTests: [PhysioTestStored]
    let completedTests: [PhysioTestStored]

    var body: some ChartContent {
        drawActiveTests()
        drawCompletedTests()
    }

    private func drawActiveTests() -> some ChartContent {
        ForEach(activeTests) { test in
            let start = test.startDate ?? Date()
            let end = Date() // Active test extends to now

            RectangleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", 400)
            )
            .foregroundStyle(Color.orange.opacity(0.08))
        }
    }

    private func drawCompletedTests() -> some ChartContent {
        ForEach(completedTests) { test in
            let start = test.startDate ?? Date()
            let end = test.endDate ?? Date()

            RectangleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                yStart: .value("Bottom", 0),
                yEnd: .value("Top", 400)
            )
            .foregroundStyle(Color.orange.opacity(0.05))
        }
    }
}
