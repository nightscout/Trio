import SwiftDate
import SwiftUI

/// A SwiftUI view displaying statistics about the looping process in an Automated Insulin Delivery (AID) system.
struct LoopStatsView: View {
    /// The list of loop statistics records used to generate the statistics.
    let statsData: [LoopStatsProcessedData]

    /// The main body of the `LoopStatsView`, displaying loop statistics.
    var body: some View {
        if let successfulStats = statsData.first(where: { $0.category == .successfulLoop }) {
            HStack {
                StatChartUtils.statView(
                    title: String(localized: "Loops"),
                    value: successfulStats.count.formatted()
                )
                Spacer()
                StatChartUtils.statView(
                    title: String(localized: "Interval"),
                    value: (successfulStats.medianInterval / 60)
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "m"
                )
                Spacer()
                StatChartUtils.statView(
                    title: String(localized: "Duration"),
                    value: successfulStats.medianDuration
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "s"
                )
                Spacer()
                StatChartUtils.statView(
                    title: String(localized: "Success"),
                    value: (successfulStats.percentage / 100)
                        .formatted(.percent.grouping(.never).rounded().precision(.fractionLength(1)))
                )
                Spacer()
                StatChartUtils.statView(
                    title: String(localized: "Days"),
                    value: successfulStats.totalDays.description
                )
            }
            .padding()
        }
    }
}
