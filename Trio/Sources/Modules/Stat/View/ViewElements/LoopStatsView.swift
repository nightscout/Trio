import SwiftDate
import SwiftUI

/// A SwiftUI view displaying statistics about the looping process in an Automated Insulin Delivery (AID) system.
struct LoopStatsView: View {
    /// The upper glucose limit used for loop evaluation.
    let highLimit: Decimal
    /// The lower glucose limit used for loop evaluation.
    let lowLimit: Decimal
    /// The unit of measurement for blood glucose values (e.g., mg/dL or mmol/L).
    let units: GlucoseUnits
    /// The display unit for estimated HbA1c values.
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit
    /// The list of loop statistics records used to generate the statistics.
    let loopStatRecords: [LoopStatRecord]

    /// The main body of the `LoopStatsView`, displaying loop statistics.
    var body: some View {
        loops
    }

    /// A computed property that calculates and displays various loop statistics such as:
    /// - Number of loops
    /// - Average interval between loops
    /// - Median loop duration
    /// - Loop success rate
    private var loops: some View {
        let loops = loopStatRecords
        // Retrieve the first (earliest) and last (most recent) loop timestamps
        let previous = loops.last?.end ?? Date()
        let current = loops.first?.start ?? Date()
        // Calculate the total duration of recorded loops in days
        let totalTime = (current - previous).timeInterval / 8.64E4

        // Extract loop durations
        let durationArray = loops.compactMap(\.duration)
        let durationArrayCount = durationArray.count
        let medianDuration = StatChartUtils.medianCalculationDouble(array: durationArray)

        // Count successful loops
        let successNR = loops.compactMap(\.loopStatus).filter { $0!.contains("Success") }.count
        let errorNR = durationArrayCount - successNR
        let total = Double(successNR + errorNR) == 0 ? 1 : Double(successNR + errorNR)
        let successRate: Double? = (Double(successNR) / total) * 100

        // Calculate the number of loops per day
        let loopNr = totalTime <= 1 ? total : round(total / (totalTime != 0 ? totalTime : 1))

        // Calculate the average loop interval
        let intervalArray = loops.compactMap { $0.interval as Double }
        let count = intervalArray.count != 0 ? intervalArray.count : 1
        let intervalAverage = intervalArray.reduce(0, +) / Double(count)

        return HStack {
            StatChartUtils.statView(title: String(localized: "Loops"), value: loopNr.formatted())
            Spacer()
            StatChartUtils.statView(
                title: String(localized: "Interval"),
                value: intervalAverage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "m"
            )
            Spacer()
            StatChartUtils.statView(
                title: String(localized: "Duration"),
                value: (medianDuration / 1000).formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + "s"
            )
            Spacer()
            StatChartUtils.statView(
                title: String(localized: "Success"),
                value: ((successRate ?? 100) / 100).formatted(.percent.grouping(.never).rounded().precision(.fractionLength(1)))
            )
        }
        .padding()
    }
}
