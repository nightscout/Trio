import Charts
import CoreData
import SwiftDate
import SwiftUI

struct GlucoseSectorChart: View {
    let highLimit: Decimal
    let units: GlucoseUnits
    let glucose: [GlucoseStored]
    let timeInRangeType: TimeInRangeType
    let showChart: Bool

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
        if glucose.count < 1 {
            Text("No glucose readings found.")
        } else {
            HStack(alignment: .center, spacing: 20) {
                // Calculate total number of glucose readings
                let total = Decimal(glucose.count)
                // Count readings greater than high limit (180 mg/dL)
                let high = glucose.filter { $0.glucose > Int(highLimit) }.count
                // Count readings between low limit (TITR: 70 mg/dL, TING 63 mg/dL) and 140 mg/dL (tight control)
                let tight = glucose
                    .filter { $0.glucose >= timeInRangeType.bottomThreshold && $0.glucose <= timeInRangeType.topThreshold }.count
                // Count readings between 140 and high limit (normal range)
                let normal = glucose.filter { $0.glucose >= timeInRangeType.bottomThreshold && $0.glucose <= Int(highLimit) }
                    .count
                // Count readings less than low limit (low) (70 mg/dL if not showing chart, otherwise 70 for TITR and 63 for TING)
                let low = glucose.filter { $0.glucose < (showChart ? Int(timeInRangeType.bottomThreshold) : 70) }.count
                // Count readings less than moderately low limit (63 mg/dL)
                let moderatelyLow = glucose.filter { $0.glucose < 63 }.count
                // Count readings less than moderately high limit (220 mg/dL)
                let moderatelyHigh = glucose.filter { $0.glucose > 220 }.count
                // Count readings less than very low limit (54 mg/dL)
                let veryLow = glucose.filter { $0.glucose < 54 }.count
                // Count readings less than very high limit (250 mg/dL)
                let veryHigh = glucose.filter { $0.glucose > 250 }.count

                let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
                let sumReadings = justGlucoseArray.reduce(0, +)

                let glucoseAverage = Decimal(sumReadings) / total
                let medianGlucose = StatChartUtils.medianCalculation(array: justGlucoseArray)

                let lowPercentage = Decimal(low) / total * 100
                let tightPercentage = Decimal(tight) / total * 100
                let inRangePercentage = Decimal(normal) / total * 100
                let highPercentage = Decimal(high) / total * 100
                let moderatelyLowPercentage = Decimal(moderatelyLow) / total * 100
                let moderatelyHighPercentage = Decimal(moderatelyHigh) / total * 100
                let veryLowPercentage = Decimal(veryLow) / total * 100
                let veryHighPercentage = Decimal(veryHigh) / total * 100

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            "\(Decimal(timeInRangeType.bottomThreshold).formatted(for: units))-\(highLimit.formatted(for: units))"
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        Text(formatPercentage(inRangePercentage, tight: true))
                            .foregroundStyle(Color.loopGreen)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            "\(Decimal(timeInRangeType.bottomThreshold).formatted(for: units))-\(Decimal(timeInRangeType.topThreshold).formatted(for: units))"
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        Text(formatPercentage(tightPercentage, tight: true))
                            .foregroundStyle(Color.green)
                    }
                }.padding(.leading, 5)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("> \(highLimit.formatted(for: units))").font(.subheadline)
                            .foregroundStyle(Color.secondary)
                        Text(formatPercentage(highPercentage, tight: true))
                            .foregroundStyle(Color.loopYellow)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            "< \(Decimal(showChart ? timeInRangeType.bottomThreshold : 70).formatted(for: units))"
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        Text(formatPercentage(lowPercentage, tight: true))
                            .foregroundStyle(Color.red)
                    }
                }
                // If not showing chart, show extra stats
                if !showChart {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("> \(Decimal(220).formatted(for: units))").font(.subheadline)
                                .foregroundStyle(Color.secondary)
                            Text(formatPercentage(moderatelyHighPercentage, tight: true))
                                .foregroundStyle(Color.loopYellow)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(
                                "< \(Decimal(63).formatted(for: units))"
                            )
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            Text(formatPercentage(moderatelyLowPercentage, tight: true))
                                .foregroundStyle(Color.red)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("> \(Decimal(250).formatted(for: units))").font(.subheadline)
                                .foregroundStyle(Color.secondary)
                            Text(formatPercentage(veryHighPercentage, tight: true))
                                .foregroundStyle(Color.orange)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(
                                "< \(Decimal(54).formatted(for: units))"
                            )
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            Text(formatPercentage(veryLowPercentage, tight: true))
                                .foregroundStyle(Color.purple)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(showChart ? "Average" : "Avg").font(.subheadline).foregroundStyle(Color.secondary)
                        Text(
                            units == .mgdL ? glucoseAverage
                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) : glucoseAverage
                                .asMmolL
                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                        )
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(showChart ? "Median" : "Med").font(.subheadline).foregroundStyle(Color.secondary)
                        Text(
                            units == .mgdL ? medianGlucose
                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) : medianGlucose
                                .asMmolL
                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))
                        )
                    }
                }

                if showChart {
                    Chart {
                        ForEach(rangeData, id: \.range) { data in
                            SectorMark(
                                angle: .value("Percentage", data.count),
                                innerRadius: .ratio(0.618),
                                outerRadius: selectedRange == data.range ? 100 : 80
                            )
                            .foregroundStyle(data.color)
                        }
                    }
                    .chartAngleSelection(value: $selectedCount)
                    .frame(height: 100)
                }
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
        let lowCount = glucose.filter { $0.glucose < timeInRangeType.bottomThreshold }.count
        // Calculate in-range readings by subtracting high and low counts from total
        let inRangeCount = total - highCount - lowCount

        // Return array of tuples with range data
        return [
            (.high, highCount, Decimal(highCount) / Decimal(total) * 100, .loopYellow),
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
        let total = Decimal(glucose.count)

        switch range {
        case .high:
            let veryHigh = glucose.filter { $0.glucose > 250 }.count
            let high = glucose.filter { $0.glucose > Int(highLimit) && $0.glucose <= 250 }.count

            let highGlucoseValues = glucose.filter { $0.glucose > Int(highLimit) }
            let highGlucoseValuesAsInt = highGlucoseValues.map { Int($0.glucose) }
            let (average, median, standardDeviation) = calculateDetailedStatistics(for: highGlucoseValuesAsInt)

            return RangeDetail(
                title: String(localized: "High Glucose"),
                color: .loopYellow,
                items: [
                    (
                        String(localized: "Very High (>\(Decimal(250).formatted(for: units)))"),
                        formatPercentage(Decimal(veryHigh) / total * 100)
                    ),
                    (
                        String(localized: "High (\(highLimit.formatted(for: units))-\(Decimal(250).formatted(for: units)))"),
                        formatPercentage(Decimal(high) / total * 100)
                    ),
                    (String(localized: "Average"), average.formatted(for: units)),
                    (String(localized: "Median"), median.formatted(for: units)),
                    (String(localized: "SD"), formatSD(standardDeviation))
                ]
            )

        case .inRange:
            let tight = glucose
                .filter { $0.glucose >= Int(timeInRangeType.bottomThreshold) && $0.glucose <= timeInRangeType.topThreshold }.count
            let glucoseValues = glucose.filter { $0.glucose >= timeInRangeType.bottomThreshold && $0.glucose <= Int(highLimit) }
            let glucoseValuesAsInt = glucoseValues.map { Int($0.glucose) }
            let (average, median, standardDeviation) = calculateDetailedStatistics(for: glucoseValuesAsInt)

            return RangeDetail(
                title: String(localized: "In Range"),
                color: .green,
                items: [
                    (
                        String(
                            localized: "Normal (\(Decimal(timeInRangeType.bottomThreshold).formatted(for: units))-\(highLimit.formatted(for: units)))"
                        ),
                        formatPercentage(Decimal(glucoseValues.count) / total * 100)
                    ),
                    (
                        String(
                            localized: "\(timeInRangeType == .timeInTightRange ? "TITR" : "TING") (\(Decimal(timeInRangeType.bottomThreshold).formatted(for: units))-\(Decimal(timeInRangeType.topThreshold).formatted(for: units)))"
                        ),
                        formatPercentage(Decimal(tight) / total * 100)
                    ),
                    (String(localized: "Average"), average.formatted(for: units)),
                    (String(localized: "Median"), median.formatted(for: units)),
                    (String(localized: "SD"), formatSD(standardDeviation))
                ]
            )

        case .low:
            let veryLow = glucose.filter { $0.glucose <= 54 }.count
            let low = glucose.filter { $0.glucose > 54 && $0.glucose < timeInRangeType.bottomThreshold }.count

            let lowGlucoseValues = glucose.filter { $0.glucose < timeInRangeType.bottomThreshold }
            let lowGlucoseValuesAsInt = lowGlucoseValues.map { Int($0.glucose) }
            let (average, median, standardDeviation) = calculateDetailedStatistics(for: lowGlucoseValuesAsInt)

            return RangeDetail(
                title: String(localized: "Low Glucose"),
                color: .red,
                items: [
                    (
                        String(
                            localized: "Low (\(Decimal(54).formatted(for: units))-\(Decimal(timeInRangeType.bottomThreshold).formatted(for: units)))"
                        ),
                        formatPercentage(Decimal(low) / total * 100)
                    ),
                    (
                        String(localized: "Very Low (<\(Decimal(54).formatted(for: units))"),
                        formatPercentage(Decimal(veryLow) / total * 100)
                    ),
                    (String(localized: "Average"), average.formatted(for: units)),
                    (String(localized: "Median"), median.formatted(for: units)),
                    (String(localized: "SD"), formatSD(standardDeviation))
                ]
            )
        }
    }

    /// Formats a percentage value to a string with one decimal place.
    /// - Parameter value: A decimal value representing the percentage.
    /// - Returns: A formatted percentage string
    private func formatPercentage(_ value: Decimal, tight: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = value == 100 ? 0 : 1
        formatter.maximumFractionDigits = value == 100 ? 0 : 1
        if tight {
            formatter.positiveSuffix = "%"
        }
        return formatter.string(from: NSDecimalNumber(decimal: value / 100)) ?? "0%"
    }

    /// Calculates statistical values for a given array of glucose readings.
    /// - Parameter values: An array of glucose readings as integers.
    /// - Returns: A tuple containing the average, median, and standard deviation.
    private func calculateDetailedStatistics(for values: [Int]) -> (Decimal, Decimal, Double) {
        guard !values.isEmpty else { return (0, 0, 0) }

        let total = values.reduce(0, +)
        let average = Decimal(total / values.count)
        let median = Decimal(StatChartUtils.medianCalculation(array: values))

        let sumOfSquares = values.reduce(0.0) { sum, value in
            sum + pow(Double(value) - Double(average), 2)
        }

        let standardDeviation = sqrt(sumOfSquares / Double(values.count))
        return (average, median, standardDeviation)
    }

    /// Formats the standard deviation value based on glucose units.
    /// - Parameter sd: The standard deviation as a Double.
    /// - Returns: A formatted string representing the standard deviation.
    private func formatSD(_ sd: Double) -> String {
        units == .mgdL ? sd.formatted(
            .number.grouping(.never).rounded().precision(.fractionLength(0))
        ) : sd.formattedAsMmolL
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
