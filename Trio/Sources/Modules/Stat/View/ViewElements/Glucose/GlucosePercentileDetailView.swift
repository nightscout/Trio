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
        // Explicitly-typed locals: without them the repeated `type == selectedPercentile`
        // ternaries (Color vs .primary/.secondary/.clear) across this modifier chain make the
        // Swift type-checker time out on some build configurations.
        let isSelected = type == selectedPercentile
        let valueString = Decimal(value).formatted(for: units)
        let valueColor: Color = isSelected ? .purple : .primary
        let labelColor: Color = isSelected ? .purple : .secondary
        let fillColor: Color = isSelected ? Color.purple.opacity(0.1) : .clear
        let borderColor: Color = isSelected ? .purple : .clear

        return VStack(spacing: 2) {
            Text(valueString)
                .font(.callout.monospacedDigit())
                .foregroundStyle(valueColor)

            Text(label)
                .font(.caption2)
                .foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                // Toggle selection on tap
                selectedPercentile = isSelected ? nil : type
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(valueString))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            withAnimation {
                selectedPercentile = isSelected ? nil : type
            }
        }
    }
}
