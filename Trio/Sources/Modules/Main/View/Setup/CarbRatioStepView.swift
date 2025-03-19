//
//  CarbRatioStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import SwiftUI

/// Carb ratio step view for setting insulin-to-carb ratio.
struct CarbRatioStepView: View {
    @State var onboardingData: OnboardingData
    @State private var showTimeSelector = false
    @State private var selectedRatioIndex: Int?

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your carb ratio tells how many grams of carbohydrates one unit of insulin will cover.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Carb ratios list
            VStack(alignment: .leading, spacing: 10) {
                Text("Carb Ratios")
                    .font(.headline)

                if onboardingData.items.isEmpty {
                    // Add default entry if no items exist
                    Button("Add Initial Carb Ratio") {
                        onboardingData.addCarbRatio()
                    }
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
                } else {
                    ForEach(Array(onboardingData.items.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            // Time display
                            Text(
                                dateFormatter
                                    .string(from: Date(timeIntervalSince1970: onboardingData.timeValues[item.timeIndex]))
                            )
                            .frame(width: 80, alignment: .leading)

                            // Ratio slider
                            Slider(
                                value: Binding(
                                    get: { Double(truncating: onboardingData.rateValues[item.rateIndex] as NSNumber) },
                                    set: { newValue in
                                        // Find closest match in rateValues array
                                        let newIndex = onboardingData.rateValues
                                            .firstIndex { abs(Double($0) - newValue) < 0.05 } ?? item.rateIndex
                                        onboardingData.items[index].rateIndex = newIndex
                                    }
                                ),
                                in: Double(truncating: onboardingData.rateValues.first! as NSNumber) ...
                                    Double(truncating: onboardingData.rateValues.last! as NSNumber),
                                step: 0.5
                            )
                            .accentColor(.orange)

                            // Display the current value
                            Text("\(formatter.string(from: onboardingData.rateValues[item.rateIndex] as NSNumber) ?? "--") g/U")
                                .frame(width: 70, alignment: .trailing)

                            // Delete button (not for the first entry at 00:00)
                            if index > 0 {
                                Button(action: {
                                    onboardingData.items.remove(at: index)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }

            // Add new carb ratio button
            if !onboardingData.items.isEmpty && onboardingData.items.count < 24 {
                Button(action: {
                    showTimeSelector = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Carb Ratio")
                    }
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Example calculation based on first carb ratio
            if !onboardingData.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example Calculation")
                        .font(.headline)
                        .padding(.top)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("For 45g of carbs, you would need:")
                            .font(.subheadline)

                        let insulinNeeded = 45 /
                            Double(truncating: onboardingData.rateValues[onboardingData.items.first!.rateIndex] as NSNumber)
                        Text(
                            "45g ÷ \(formatter.string(from: onboardingData.rateValues[onboardingData.items.first!.rateIndex] as NSNumber) ?? "--") = \(String(format: "%.1f", insulinNeeded)) units of insulin"
                        )
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding(.vertical, 4)
                }

                // Information about the carb ratio
                VStack(alignment: .leading, spacing: 8) {
                    Text("What This Means")
                        .font(.headline)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("• A ratio of 10 g/U means 1 unit of insulin covers 10g of carbs")
                        Text("• A lower number means you need more insulin for the same amount of carbs")
                        Text("• A higher number means you need less insulin for the same amount of carbs")
                        Text("• Different times of day may require different ratios")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            // Visualization of carb ratio if we have ratios defined
            if !onboardingData.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Visual Reference")
                        .font(.headline)
                        .padding(.top)

                    HStack(spacing: 20) {
                        VStack {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text(
                                "\(formatter.string(from: onboardingData.rateValues[onboardingData.items.first!.rateIndex] as NSNumber) ?? "--")g"
                            )
                            .font(.headline)
                            Text("Carbs")
                                .font(.caption)
                        }

                        Text("=")
                            .font(.title)

                        VStack {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                            Text("1U")
                                .font(.headline)
                            Text("Insulin")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .actionSheet(isPresented: $showTimeSelector) {
            var buttons: [ActionSheet.Button] = []

            // Find available time slots in 1-hour increments
            for hour in 0 ..< 24 {
                let hourInMinutes = hour * 60
                // Calculate timeIndex for this hour
                let timeIndex = onboardingData.timeValues.firstIndex { abs($0 - Double(hourInMinutes * 60)) < 10 } ?? 0

                // Check if this hour is already in the profile
                if !onboardingData.items.contains(where: { $0.timeIndex == timeIndex }) {
                    buttons.append(.default(Text("\(String(format: "%02d:00", hour))")) {
                        // Get the current ratio from the last item
                        let rateIndex = onboardingData.items.last?.rateIndex ?? 0
                        // Create new item with the specified time
                        let newItem = CarbRatioEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
                        // Add the new item and sort the list
                        onboardingData.items.append(newItem)
                        onboardingData.items.sort(by: { $0.timeIndex < $1.timeIndex })
                    })
                }
            }

            buttons.append(.cancel())

            return ActionSheet(
                title: Text("Select Start Time"),
                message: Text("Choose when this carb ratio should start"),
                buttons: buttons
            )
        }
    }
}
