import SwiftUI

/// The SmartSense sensitivity widget shown on the treatment screen.
/// Displays the computed sensitivity adjustment with a slider for user override.
struct SmartSenseSummaryView: View {
    let result: SmartSenseResult
    @Binding var userOverride: Double // The user's chosen adjustment (e.g. +0.09)
    let maxAdjustment: Double

    @State private var showBreakdown = false

    private var displayPercent: Int {
        Int((userOverride * 100).rounded())
    }

    private var suggestedPercent: Int {
        Int((result.blendedSuggestion * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .foregroundStyle(.blue)
                Text("Smart Sense")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%+d%%", displayPercent))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(displayPercent > 0 ? .red : displayPercent < 0 ? .green : .primary)
            }

            // Slider
            VStack(spacing: 4) {
                Slider(
                    value: $userOverride,
                    in: -maxAdjustment ... maxAdjustment,
                    step: 0.01
                )
                .tint(userOverride > 0 ? .red : userOverride < 0 ? .green : .blue)

                HStack {
                    Text("-\(Int(maxAdjustment * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("0%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+\(Int(maxAdjustment * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Source summary
            HStack(spacing: 16) {
                if result.garminDataAvailable {
                    sourceTag(
                        label: "Garmin",
                        value: String(format: "%+.0f%%", result.garminComposite * 100),
                        split: Int(result.masterSplit.garmin * 100)
                    )
                }
                sourceTag(
                    label: "Autosens",
                    value: String(format: "%+.0f%%", result.autosensContribution * 100),
                    split: Int(result.masterSplit.autosens * 100)
                )
            }

            // Expand/collapse breakdown
            Button {
                withAnimation { showBreakdown.toggle() }
            } label: {
                HStack {
                    Text(showBreakdown ? "Hide Breakdown" : "Show Breakdown")
                        .font(.caption)
                    Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            if showBreakdown {
                breakdownView
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Source Tag

    private func sourceTag(label: String, value: String, split: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
            Text("(\(split)%)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Breakdown

    private var breakdownView: some View {
        VStack(alignment: .leading, spacing: 6) {
            let availableFactors = result.garminFactors.filter { $0.value != "N/A" && $0.value != "Unavailable" }

            if !availableFactors.isEmpty {
                ForEach(availableFactors, id: \.factor) { factor in
                    HStack {
                        Text(factor.factor)
                            .font(.caption)
                            .frame(width: 120, alignment: .leading)
                        Text(factor.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Text(String(format: "%+.1f%%", factor.weightedImpact * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(
                                factor.weightedImpact > 0.001 ? .red :
                                    factor.weightedImpact < -0.001 ? .green : .secondary
                            )
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }

            // Always show the autosens contribution
            HStack {
                Text("Autosens Ratio")
                    .font(.caption)
                    .frame(width: 120, alignment: .leading)
                Text(String(format: "%.2f", result.autosensRatio))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Spacer()
                Text(String(format: "%+.1f%%", result.autosensContribution * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        result.autosensContribution > 0.001 ? .red :
                            result.autosensContribution < -0.001 ? .green : .secondary
                    )
                    .frame(width: 50, alignment: .trailing)
            }

            // Final ratio
            HStack {
                Text("Final Ratio")
                    .font(.caption.weight(.medium))
                    .frame(width: 120, alignment: .leading)
                Text(String(format: "%.2f", result.finalRatio))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 80, alignment: .leading)
                Spacer()
                Text(String(format: "%+.1f%%", (result.finalRatio - 1.0) * 100))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(
                        result.finalRatio > 1.001 ? .red :
                            result.finalRatio < 0.999 ? .green : .secondary
                    )
                    .frame(width: 50, alignment: .trailing)
            }

            if !result.garminDataAvailable {
                Text("Garmin data unavailable — using autosens only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Meal Picker View

/// Shows detected Cronometer meals from the last 4 hours for the user to select.
/// Dosed meals display a badge but can still be re-selected (e.g. if the bolus was cancelled).
struct CronometerMealPickerView: View {
    let meals: [DetectedMeal]
    let onSelect: (DetectedMeal) -> Void
    let onDismiss: () -> Void

    private var recentMeals: [DetectedMeal] {
        let fourHoursAgo = Date().addingTimeInterval(-4 * 60 * 60)
        return meals.filter { $0.detectedAt > fourHoursAgo }
            .sorted { $0.detectedAt > $1.detectedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.orange)
                Text("Detected Meals")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Skip") { onDismiss() }
                    .font(.subheadline)
            }

            if recentMeals.isEmpty {
                Text("No meals detected from Cronometer in the last 4 hours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(recentMeals) { meal in
                    Button {
                        onSelect(meal)
                    } label: {
                        mealRow(meal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func mealRow(_ meal: DetectedMeal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(meal.label)
                        .font(.subheadline.weight(.medium))
                    if meal.isDosed {
                        Text("Dosed")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue))
                    }
                }
                HStack(spacing: 12) {
                    macroTag("C", value: meal.carbs, color: .green)
                    macroTag("F", value: meal.fat, color: .yellow)
                    macroTag("P", value: meal.protein, color: .red)
                    if meal.fiber > 0 {
                        macroTag("Fb", value: meal.fiber, color: .brown)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func macroTag(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text("\(Int(value))g")
                .font(.caption2)
        }
    }
}
