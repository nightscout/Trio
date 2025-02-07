import Charts
import Foundation
import SwiftUI

struct GlucoseTargetsView: ChartContent {
    let targetProfiles: [TargetProfile]

    var body: some ChartContent {
        drawGlucoseTargets(for: targetProfiles)
    }

    /**
     Draws glucose target ranges on the chart

     - Returns: A ChartContent containing line marks representing target glucose ranges
     */
    private func drawGlucoseTargets(for targetProfiles: [TargetProfile]) -> some ChartContent {
        // Draw target lines for each profile
        ForEach(targetProfiles, id: \.self) { profile in
            LineMark(
                x: .value("Time", Date(timeIntervalSinceReferenceDate: profile.startTime)),
                y: .value("Target", profile.value)
            )
            .lineStyle(.init(lineWidth: 1))
            .foregroundStyle(Color.green.gradient)

            LineMark(
                x: .value("Time", Date(timeIntervalSinceReferenceDate: profile.endTime)),
                y: .value("Target", profile.value)
            )
            .lineStyle(.init(lineWidth: 1))
            .foregroundStyle(Color.green.gradient)
        }
    }
}
