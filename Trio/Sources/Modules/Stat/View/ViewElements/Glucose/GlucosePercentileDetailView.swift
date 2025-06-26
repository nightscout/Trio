import SwiftUI

struct GlucoseDailyPercentileDetailView: View {
    let dayData: GlucoseDailyPercentileStats
    let units: GlucoseUnits
    let dateRangeText: String

    // Binding to the parent's selectedPercentile
    @Binding var selectedPercentile: GlucosePercentileType?

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(dateRangeText)
                .font(.subheadline.weight(.medium))
                .padding(.bottom, 4)

            // Only show percentile details if we have valid data
            if dayData.median > 0 {
                // Improved percentile display
                HStack(spacing: 0) {
                    percentileItem(label: "Min", value: round(dayData.minimum), type: .minimum)
                    percentileItem(label: "10%", value: round(dayData.percentile10), type: .percentile10)
                    percentileItem(label: "25%", value: round(dayData.percentile25), type: .percentile25)
                    percentileItem(label: "Median", value: round(dayData.median), type: .median)
                    percentileItem(label: "75%", value: round(dayData.percentile75), type: .percentile75)
                    percentileItem(label: "90%", value: round(dayData.percentile90), type: .percentile90)
                    percentileItem(label: "Max", value: round(dayData.maximum), type: .maximum)
                }
                .padding(.vertical, 8)
            } else {
                Text("No glucose data available for this day")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    /// Creates a single percentile item for the detail view
    private func percentileItem(
        label: String,
        value: Double,
        type: GlucosePercentileType
    ) -> some View {
        VStack(spacing: 2) {
            Text(Decimal(value).formatted(for: units))
                .font(.callout.monospacedDigit())
                .foregroundStyle(type == selectedPercentile ? Color.purple : .primary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(type == selectedPercentile ? Color.purple : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(type == selectedPercentile ? Color.purple.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(type == selectedPercentile ? Color.purple : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                // Toggle selection on tap
                selectedPercentile = (selectedPercentile == type) ? nil : type
            }
        }
    }
}
