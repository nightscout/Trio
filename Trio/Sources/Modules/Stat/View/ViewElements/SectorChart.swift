import Charts
import CoreData
import SwiftDate
import SwiftUI

struct SectorChart: View {
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let glucose: [GlucoseStored]

    @State private var selectedCount: Int?
    @State private var selectedRange: GlucoseRange?

    /// Represents the different ranges of glucose values that can be displayed in the sector chart
    /// - high: Above target range
    /// - inRange: Within target range
    /// - low: Below target range
    private enum GlucoseRange: String, Plottable {
        case high = "High"
        case inRange = "In Range"
        case low = "Low"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            // Calculate total number of glucose readings
            let total = Decimal(glucose.count)
            // Count readings between high limit and 250 mg/dL (high)
            let high = glucose.filter { $0.glucose > Int(highLimit) }.count
            // Count readings between low limit and 140 mg/dL (tight control)
            let tight = glucose.filter { $0.glucose >= Int(lowLimit) && $0.glucose <= 140 }.count
            // Count readings between 140 and high limit (normal range)
            let normal = glucose.filter { $0.glucose >= Int(lowLimit) && $0.glucose <= Int(highLimit) }.count
            // Count readings between 54 and low limit (low)
            let low = glucose.filter { $0.glucose < Int(lowLimit) }.count

            let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
            let sumReadings = justGlucoseArray.reduce(0, +)

            let glucoseAverage = Decimal(sumReadings) / total
            let medianGlucose = BareStatisticsView.medianCalculation(array: justGlucoseArray)

            let lowPercentage = Decimal(low) / total * 100
            let tightPercentage = Decimal(tight) / total * 100
            let inRangePercentage = Decimal(normal) / total * 100
            let highPercentage = Decimal(high) / total * 100

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("70-180").font(.subheadline).foregroundStyle(Color.secondary)
                    Text(inRangePercentage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + "%")
                        .foregroundStyle(Color.loopGreen)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("70-140").font(.subheadline).foregroundStyle(Color.secondary)
                    Text(tightPercentage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + "%")
                        .foregroundStyle(Color.green)
                }
            }.padding(.leading, 5)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("> 180").font(.subheadline).foregroundStyle(Color.secondary)
                    Text(highPercentage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + "%")
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("< 54").font(.subheadline).foregroundStyle(Color.secondary)
                    Text(lowPercentage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + "%")
                        .foregroundStyle(Color.loopRed)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Average").font(.subheadline).foregroundStyle(Color.secondary)
                    Text(glucoseAverage.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Median").font(.subheadline).foregroundStyle(Color.secondary)
                    Text(medianGlucose.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))))
                }
            }

            Chart {
                ForEach(rangeData, id: \.range) { data in
                    SectorMark(
                        angle: .value("Percentage", data.count),
                        innerRadius: .ratio(0.618),
                        outerRadius: selectedRange == data.range ? 100 : 80,
                        angularInset: 1.5
                    )
                    .foregroundStyle(data.color)
                }
            }
            .chartAngleSelection(value: $selectedCount)
            .frame(height: 100)
        }
        .onChange(of: selectedCount) { _, newValue in
            if let newValue {
                withAnimation {
                    getSelectedRange(value: newValue)
                }
            } else {
                withAnimation {
                    selectedRange = nil
                }
            }
        }
        .overlay(alignment: .top) {
            if let selectedRange {
                let data = getDetailedData(for: selectedRange)
                RangeDetailPopover(data: data)
                    .transition(.scale.combined(with: .opacity))
                    .offset(y: -150) // TODO: make this dynamic
            }
        }
    }

    /// Calculates statistics about glucose ranges and returns data for the sector chart
    ///
    /// This computed property processes glucose readings and categorizes them into high, in-range, and low ranges.
    /// For each range, it calculates:
    /// - The count of readings in that range
    /// - The percentage of total readings
    /// - The associated color for visualization
    ///
    /// - Returns: An array of tuples containing range data, where each tuple has:
    ///   - range: The glucose range category (high, in-range, or low)
    ///   - count: Number of readings in that range
    ///   - percentage: Percentage of total readings in that range
    ///   - color: Color used to represent that range in the chart
    private var rangeData: [(range: GlucoseRange, count: Int, percentage: Decimal, color: Color)] {
        let total = glucose.count
        // Return empty array if no glucose readings available
        guard total > 0 else { return [] }

        // Count readings above high limit
        let highCount = glucose.filter { $0.glucose > Int(highLimit) }.count
        // Count readings below low limit
        let lowCount = glucose.filter { $0.glucose < Int(lowLimit) }.count
        // Calculate in-range readings by subtracting high and low counts from total
        let inRangeCount = total - highCount - lowCount

        // Return array of tuples with range data
        return [
            (.high, highCount, Decimal(highCount) / Decimal(total) * 100, .orange),
            (.inRange, inRangeCount, Decimal(inRangeCount) / Decimal(total) * 100, .green),
            (.low, lowCount, Decimal(lowCount) / Decimal(total) * 100, .red)
        ]
    }

    /// Determines which glucose range was selected based on a cumulative value
    ///
    /// This function takes a value representing a point in the cumulative total of glucose readings
    /// and determines which range (high, in-range, or low) that point falls into.
    /// It updates the selectedRange state variable when the appropriate range is found.
    ///
    /// - Parameter value: An integer representing a point in the cumulative total of readings
    private func getSelectedRange(value: Int) {
        // Keep track of running total as we check each range
        var cumulativeTotal = 0

        // Find first range where value falls within its cumulative count
        _ = rangeData.first { data in
            cumulativeTotal += data.count
            if value <= cumulativeTotal {
                selectedRange = data.range
                return true
            }
            return false
        }
    }

    /// Gets detailed statistics for a specific glucose range category
    ///
    /// This function calculates detailed statistics for a given glucose range (high, in-range, or low),
    /// breaking down the readings into subcategories and calculating percentages.
    ///
    /// - Parameter range: The glucose range category to analyze
    /// - Returns: A RangeDetail object containing the title, color and detailed statistics
    private func getDetailedData(for range: GlucoseRange) -> RangeDetail {
        // Calculate total number of glucose readings
        let total = Decimal(glucose.count)

        switch range {
        case .high:
            // Count readings above 250 mg/dL (very high)
            let veryHigh = glucose.filter { $0.glucose > 250 }.count
            // Count readings between high limit and 250 mg/dL (high)
            let high = glucose.filter { $0.glucose > Int(highLimit) && $0.glucose <= 250 }.count

            // Format glucose values
            let highLimitTreshold = units == .mmolL ? Decimal(Int(highLimit)).asMmolL : highLimit
            let veryHighThreshold = units == .mmolL ? Decimal(250).asMmolL : 250

            let highGlucoseValues = glucose.filter { $0.glucose > Int(highLimit) }
            let highGlucoseValuesAsInt = highGlucoseValues.compactMap({ each in Int(each.glucose as Int16) })
            let highGlucoseTotal = highGlucoseValuesAsInt.reduce(0, +)

            let average = Decimal(highGlucoseTotal / highGlucoseValues.count)
            let median = Decimal(BareStatisticsView.medianCalculation(array: highGlucoseValuesAsInt))

            var sumOfSquares = 0.0
            highGlucoseValuesAsInt.forEach { value in
                sumOfSquares += pow(Double(value) - Double(average), 2)
            }

            var standardDeviation = 0.0

            if average > 0 {
                standardDeviation = sqrt(sumOfSquares / Double(highGlucoseValues.count))
            }

            return RangeDetail(
                title: "High Glucose",
                color: .orange,
                items: [
                    (
                        "Very High (>\(veryHighThreshold)):",
                        formatPercentage(Decimal(veryHigh) / total * 100)
                    ),
                    (
                        "High (\(highLimitTreshold)-\(veryHighThreshold)):",
                        formatPercentage(Decimal(high) / total * 100)
                    ),
                    ("Avergage", units == .mgdL ? average.description : average.formattedAsMmolL),
                    ("Median", units == .mgdL ? median.description : median.formattedAsMmolL),
                    (
                        "SD",
                        units == .mgdL ? standardDeviation.formatted(
                            .number.grouping(.never).rounded()
                                .precision(.fractionLength(0))
                        ) : standardDeviation.asMmolL.formatted(
                            .number.grouping(.never).rounded()
                                .precision(
                                    .fractionLength(1)
                                )
                        )
                    )
                ]
            )
        case .inRange:
            // Count readings between low limit and 140 mg/dL (tight control)
            let tight = glucose.filter { $0.glucose >= Int(lowLimit) && $0.glucose <= 140 }.count
            // Count readings between 140 and high limit (normal range)
            let glucoseValues = glucose.filter { $0.glucose >= Int(lowLimit) && $0.glucose <= Int(highLimit) }

            // Format glucose values
            let lowLimitTreshold = units == .mmolL ? Decimal(Int(lowLimit)).asMmolL : lowLimit
            let highLimitTreshold = units == .mmolL ? Decimal(Int(highLimit)).asMmolL : highLimit
            let tightThresholdTreshold = units == .mmolL ? Decimal(140).asMmolL : 140

            let glucoseValuesAsInt = glucoseValues.compactMap({ each in Int(each.glucose as Int16) })
            let glucoseTotal = glucoseValuesAsInt.reduce(0, +)

            let average = Decimal(glucoseTotal / glucoseValues.count)
            let median = Decimal(BareStatisticsView.medianCalculation(array: glucoseValuesAsInt))

            var sumOfSquares = 0.0
            glucoseValuesAsInt.forEach { value in
                sumOfSquares += pow(Double(value) - Double(average), 2)
            }

            var standardDeviation = 0.0

            if average > 0 {
                standardDeviation = sqrt(sumOfSquares / Double(glucoseValues.count))
            }

            return RangeDetail(
                title: "In Range",
                color: .green,
                items: [
                    (
                        "Normal (\(lowLimitTreshold)-\(highLimitTreshold))",
                        formatPercentage(Decimal(glucoseValues.count) / total * 100)
                    ),
                    (
                        "Tight (\(lowLimitTreshold)-\(tightThresholdTreshold))",
                        formatPercentage(Decimal(tight) / total * 100)
                    ),
                    ("Avergage", units == .mgdL ? average.description : average.formattedAsMmolL),
                    ("Median", units == .mgdL ? median.description : median.formattedAsMmolL),
                    (
                        "SD",
                        units == .mgdL ? standardDeviation.formatted(
                            .number.grouping(.never).rounded()
                                .precision(.fractionLength(0))
                        ) : standardDeviation.asMmolL.formatted(
                            .number.grouping(.never).rounded()
                                .precision(
                                    .fractionLength(1)
                                )
                        )
                    )
                ]
            )
        case .low:
            // Count readings below 54 mg/dL (very low/urgent low)
            let veryLow = glucose.filter { $0.glucose <= 54 }.count
            // Count readings between 54 and low limit (low)
            let low = glucose.filter { $0.glucose > 54 && $0.glucose < Int(lowLimit) }.count

            // Format glucose values
            let lowLimitTreshold = units == .mmolL ? Decimal(Int(lowLimit)).asMmolL : lowLimit
            let veryLowThresholdTreshold = units == .mmolL ? Decimal(54).asMmolL : 54

            let lowGlucoseValues = glucose.filter { $0.glucose < Int(lowLimit) }
            let lowGlucoseValuesAsInt = lowGlucoseValues.compactMap({ each in Int(each.glucose as Int16) })
            let lowGlucoseTotal = lowGlucoseValuesAsInt.reduce(0, +)

            let average = Decimal(lowGlucoseTotal / lowGlucoseValues.count)
            let median = Decimal(BareStatisticsView.medianCalculation(array: lowGlucoseValuesAsInt))

            var sumOfSquares = 0.0
            lowGlucoseValuesAsInt.forEach { value in
                sumOfSquares += pow(Double(value) - Double(average), 2)
            }

            var standardDeviation = 0.0

            if average > 0 {
                standardDeviation = sqrt(sumOfSquares / Double(lowGlucoseValues.count))
            }

            return RangeDetail(
                title: "Low Glucose",
                color: .red,
                items: [
                    (
                        "Low (\(veryLowThresholdTreshold)-\(lowLimitTreshold))",
                        formatPercentage(Decimal(low) / total * 100)
                    ),
                    (
                        "Very Low (<\(veryLowThresholdTreshold))",
                        formatPercentage(Decimal(veryLow) / total * 100)
                    ),
                    ("Avergage", units == .mgdL ? average.description : average.formattedAsMmolL),
                    ("Median", units == .mgdL ? median.description : median.formattedAsMmolL),
                    (
                        "SD",
                        units == .mgdL ? standardDeviation.formatted(
                            .number.grouping(.never).rounded()
                                .precision(.fractionLength(0))
                        ) : standardDeviation.asMmolL.formatted(
                            .number.grouping(.never).rounded()
                                .precision(
                                    .fractionLength(1)
                                )
                        )
                    )
                ]
            )
        }
    }

    func formatPercentage(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSDecimalNumber(decimal: value / 100)) ?? "0%"
    }
}

/// Represents details about a specific glucose range category including title, color and percentage breakdowns
private struct RangeDetail {
    /// The title of this range category (e.g. "High Glucose", "In Range", "Low Glucose")
    let title: String
    /// The color used to represent this range in the UI
    let color: Color
    /// Array of tuples containing label and percentage for each sub-range
    let items: [(label: String, value: String)]
}

/// A popover view that displays detailed breakdown of glucose percentages for a range category
private struct RangeDetailPopover: View {
    let data: RangeDetail

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(data.title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(data.color)
                .padding(.bottom, 4)

            ForEach(Array(data.items.enumerated()), id: \..offset) { index, item in
                if index < 2 {
                    HStack {
                        Text(item.label)
                        Text(item.value).bold()
                    }
                    .font(.footnote)
                }
            }

            HStack(spacing: 20) {
                ForEach(Array(data.items.enumerated()), id: \..offset) { index, item in
                    if index > 1 {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.label)
                            HStack {
                                Text(item.value).bold()
                            }
                        }
                        .font(.footnote)
                    }
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.bgDarkBlue.opacity(0.9) : Color.white.opacity(0.95))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(data.color, lineWidth: 2)
                )
        }
    }
}
