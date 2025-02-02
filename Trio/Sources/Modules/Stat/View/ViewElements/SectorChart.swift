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
            Chart {
                ForEach(rangeData, id: \.range) { data in
                    SectorMark(
                        angle: .value("Percentage", data.count),
                        innerRadius: .ratio(0.618),
                        outerRadius: selectedRange == data.range ? 100 : 80,
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(data.color.gradient)
                    .annotation(position: .overlay, alignment: .center, spacing: 0) {
                        if data.percentage > 0 {
                            Text("\(Int(data.percentage))%")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .fontWeight(.bold)
                        }
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 20)
            .chartAngleSelection(value: $selectedCount)
            .chartForegroundStyleScale([
                "High": Color.orange,
                "In Range": Color.green,
                "Low": Color.red
            ])
            .padding(.vertical)
            .frame(height: 250)
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
                    .offset(y: -90) // TODO: make this dynamic
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

            return RangeDetail(
                title: "High Glucose",
                color: .orange,
                items: [
                    ("Very High (>\(veryHighThreshold) \(units.rawValue))", Decimal(veryHigh) / total * 100),
                    ("High (\(highLimitTreshold)-\(veryHighThreshold) \(units.rawValue))", Decimal(high) / total * 100)
                ]
            )
        case .inRange:
            // Count readings between low limit and 140 mg/dL (tight control)
            let tight = glucose.filter { $0.glucose >= Int(lowLimit) && $0.glucose <= 140 }.count
            // Count readings between 140 and high limit (normal range)
            let normal = glucose.filter { $0.glucose > 140 && $0.glucose <= Int(highLimit) }.count

            // Format glucose values
            let lowLimitTreshold = units == .mmolL ? Decimal(Int(lowLimit)).asMmolL : lowLimit
            let highLimitTreshold = units == .mmolL ? Decimal(Int(highLimit)).asMmolL : highLimit
            let tightThresholdTreshold = units == .mmolL ? Decimal(140).asMmolL : 140

            return RangeDetail(
                title: "In Range",
                color: .green,
                items: [
                    ("Tight (\(lowLimitTreshold)-\(tightThresholdTreshold) \(units.rawValue))", Decimal(tight) / total * 100),
                    ("Normal (\(tightThresholdTreshold)-\(highLimitTreshold) \(units.rawValue))", Decimal(normal) / total * 100)
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

            return RangeDetail(
                title: "Low Glucose",
                color: .red,
                items: [
                    ("Very Low (<\(veryLowThresholdTreshold) \(units.rawValue))", Decimal(veryLow) / total * 100),
                    ("Low (\(veryLowThresholdTreshold)-\(lowLimitTreshold) \(units.rawValue))", Decimal(low) / total * 100)
                ]
            )
        }
    }
}

/// Represents details about a specific glucose range category including title, color and percentage breakdowns
private struct RangeDetail {
    /// The title of this range category (e.g. "High Glucose", "In Range", "Low Glucose")
    let title: String
    /// The color used to represent this range in the UI
    let color: Color
    /// Array of tuples containing label and percentage for each sub-range
    let items: [(label: String, percentage: Decimal)]
}

/// A popover view that displays detailed breakdown of glucose percentages for a range category
private struct RangeDetailPopover: View {
    let data: RangeDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.title)
                .font(.subheadline)
                .fontWeight(.bold)

            ForEach(data.items, id: \.label) { item in
                HStack {
                    Text(item.label)
                    Spacer()
                    Text(formatPercentage(item.percentage))
                }
                .font(.footnote)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(data.color.gradient)
        }
    }

    private func formatPercentage(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSDecimalNumber(decimal: value / 100)) ?? "0%"
    }
}
