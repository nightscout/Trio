import Charts
import Foundation
import SwiftUI

struct ChartTempTarget: Hashable {
    let amount: Decimal
    let start: Date
    let end: Date
}

extension MainChartView {
    func drawTempTargets() -> some ChartContent {
        ForEach(chartTempTargets, id: \.self) { target in
            let targetLimited = min(max(target.amount, 0), upperLimit)

            RuleMark(
                xStart: .value("Start", target.start),
                xEnd: .value("End", target.end),
                y: .value("Value", targetLimited)
            )
            .foregroundStyle(Color.green.opacity(0.75)).lineStyle(.init(lineWidth: 8))
        }
    }

    // Calculations for temp target bar mark
    func calculateTempTargets() async {
        // Perform calculations off the main thread
        let calculatedTTs = await Task.detached { () -> [ChartTempTarget] in
            var groupedPackages: [[TempTarget]] = []
            var currentPackage: [TempTarget] = []
            var calculatedTTs: [ChartTempTarget] = []

            for target in await tempTargets {
                if target.duration > 0 {
                    if !currentPackage.isEmpty {
                        groupedPackages.append(currentPackage)
                        currentPackage = []
                    }
                    currentPackage.append(target)
                } else if let lastNonZeroTempTarget = currentPackage.last(where: { $0.duration > 0 }) {
                    // Ensure this cancel target is within the valid time range
                    if target.createdAt >= lastNonZeroTempTarget.createdAt,
                       target.createdAt <= lastNonZeroTempTarget.createdAt
                       .addingTimeInterval(TimeInterval(lastNonZeroTempTarget.duration * 60))
                    {
                        currentPackage.append(target)
                    }
                }
            }

            // Append the last group, if any
            if !currentPackage.isEmpty {
                groupedPackages.append(currentPackage)
            }

            for package in groupedPackages {
                guard let firstNonZeroTarget = package.first(where: { $0.duration > 0 }) else { continue }

                var end = firstNonZeroTarget.createdAt.addingTimeInterval(TimeInterval(firstNonZeroTarget.duration * 60))

                let earliestCancelTarget = package.filter({ $0.duration == 0 }).min(by: { $0.createdAt < $1.createdAt })

                if let earliestCancelTarget = earliestCancelTarget {
                    end = min(earliestCancelTarget.createdAt, end)
                }

                if let targetTop = firstNonZeroTarget.targetTop {
                    let adjustedTarget = await units == .mgdL ? targetTop : targetTop.asMmolL
                    calculatedTTs
                        .append(ChartTempTarget(amount: adjustedTarget, start: firstNonZeroTarget.createdAt, end: end))
                }
            }

            return calculatedTTs
        }.value

        // Update chartTempTargets on the main thread
        await MainActor.run {
            self.chartTempTargets = calculatedTTs
        }
    }
}
