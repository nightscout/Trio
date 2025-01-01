import Charts
import Foundation
import SwiftUI

struct GlucoseTargetsView: ChartContent {
    let startMarker: Date
    let endMarker: Date
    let units: GlucoseUnits
    let bgTargets: BGTargets

    var body: some ChartContent {
        drawGlucoseTargets()
    }

    private func drawGlucoseTargets() -> some ChartContent {
        var targetProfiles: [TargetProfile] = []
        let targets = bgTargets.targets

        for (index, target) in targets.enumerated() {
            let startTime = max(TimeInterval(target.offset * 60), startMarker.timeIntervalSinceReferenceDate)
            let endTime: TimeInterval = {
                if index + 1 < targets.count {
                    return min(TimeInterval(targets[index + 1].offset * 60), endMarker.timeIntervalSinceReferenceDate)
                } else {
                    return endMarker.timeIntervalSinceReferenceDate
                }
            }()

            if startTime < endTime { // Ensure valid range
                targetProfiles.append(
                    TargetProfile(
                        value: units == .mgdL ? target.low : target.low.asMmolL,
                        startTime: startTime,
                        endTime: endTime
                    )
                )
            }
        }

        // Draw Target Lines
        return ForEach(targetProfiles, id: \.self) { profile in
            // Horizontal Line for Target Range
            LineMark(
                x: .value("Time", Date(timeIntervalSince1970: profile.startTime)),
                y: .value("Value", profile.value)
            ).lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.green.gradient)

            LineMark(
                x: .value("Time", Date(timeIntervalSince1970: profile.endTime)),
                y: .value("Value", profile.value)
            ).lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.green.gradient)

            // Vertical Transition Line to the Next Profile (if exists)
            if let nextProfile = targetProfiles.first(where: { $0.startTime == profile.endTime }) {
                LineMark(
                    x: .value("Time", Date(timeIntervalSince1970: profile.endTime)),
                    y: .value("Value", profile.value)
                ).lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.green.gradient)

                LineMark(
                    x: .value("Time", Date(timeIntervalSince1970: profile.endTime)),
                    y: .value("Value", nextProfile.value)
                ).lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.green.gradient)
            }
        }
    }
}

struct TargetProfile: Hashable {
    let value: Decimal
    let startTime: TimeInterval
    let endTime: TimeInterval
}

private extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
