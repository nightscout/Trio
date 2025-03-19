//
//  GlucoseTargetStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import SwiftUI

/// Glucose target step view for setting target glucose range.
struct GlucoseTargetStepView: View {
    @State var onboardingData: OnboardingData
    @State private var showUnitPicker = false

    // Formatter for glucose values
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = onboardingData.units == .mmolL ? 1 : 0
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Unit selector
            HStack {
                Text("Blood Glucose Units")
                    .font(.headline)

                Spacer()

                Button(action: {
                    showUnitPicker.toggle()
                }) {
                    HStack {
                        Text(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")
                        Image(systemName: "chevron.down")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .actionSheet(isPresented: $showUnitPicker) {
                    ActionSheet(
                        title: Text("Select Blood Glucose Units"),
                        buttons: [
                            .default(Text("mg/dL")) {
                                onboardingData.units = .mgdL
                                // Adjust values for unit change
                                if onboardingData.units == .mgdL {
                                    onboardingData.targetLow = max(70, onboardingData.targetLow * 18)
                                    onboardingData.targetHigh = max(120, onboardingData.targetHigh * 18)
                                    onboardingData.isf = max(30, onboardingData.isf * 18)
                                }
                            },
                            .default(Text("mmol/L")) {
                                onboardingData.units = .mmolL
                                // Adjust values for unit change
                                if onboardingData.units == .mmolL {
                                    onboardingData.targetLow = max(3.9, onboardingData.targetLow / 18)
                                    onboardingData.targetHigh = max(6.7, onboardingData.targetHigh / 18)
                                    onboardingData.isf = max(1.7, onboardingData.isf / 18)
                                }
                            },
                            .cancel()
                        ]
                    )
                }
            }

            Divider()

            // Target glucose range
            VStack(alignment: .leading, spacing: 12) {
                Text("Target Glucose Range")
                    .font(.headline)

                Text("This range defines your ideal blood glucose values. Trio uses this to calculate insulin doses.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Low target
                VStack(alignment: .leading) {
                    Text("Low Target")
                        .font(.subheadline)

                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(truncating: onboardingData.targetLow as NSNumber) },
                                set: { onboardingData.targetLow = Decimal($0) }
                            ),
                            in: onboardingData.units == .mgdL ? 70 ... 120 : 3.9 ... 6.7,
                            step: onboardingData.units == .mgdL ? 1 : 0.1
                        )
                        .accentColor(.green)

                        Text(
                            "\(numberFormatter.string(from: onboardingData.targetLow as NSNumber) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")"
                        )
                        .frame(width: 80, alignment: .trailing)
                    }
                }
                .padding(.vertical, 4)

                // High target
                VStack(alignment: .leading) {
                    Text("High Target")
                        .font(.subheadline)

                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(truncating: onboardingData.targetHigh as NSNumber) },
                                set: { onboardingData.targetHigh = Decimal($0) }
                            ),
                            in: onboardingData.units == .mgdL ?
                                Double(truncating: onboardingData.targetLow as NSNumber) + 10 ... 200 :
                                Double(truncating: onboardingData.targetLow as NSNumber) + 0.6 ... 11.1,
                            step: onboardingData.units == .mgdL ? 1 : 0.1
                        )
                        .accentColor(.green)

                        Text(
                            "\(numberFormatter.string(from: onboardingData.targetHigh as NSNumber) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")"
                        )
                        .frame(width: 80, alignment: .trailing)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Target range visualization
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Target Range")
                    .font(.headline)

                HStack(spacing: 0) {
                    // Below range
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 50, height: 30)
                        .overlay(
                            Text("Low")
                                .font(.caption)
                                .foregroundColor(.red)
                        )

                    // Target range
                    Rectangle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 100, height: 30)
                        .overlay(
                            Text("Target")
                                .font(.caption)
                                .foregroundColor(.green)
                        )

                    // Above range
                    Rectangle()
                        .fill(Color.yellow.opacity(0.3))
                        .frame(width: 50, height: 30)
                        .overlay(
                            Text("High")
                                .font(.caption)
                                .foregroundColor(.orange)
                        )
                }
                .cornerRadius(8)

                // Range values
                HStack(spacing: 0) {
                    Text("\(numberFormatter.string(from: onboardingData.targetLow as NSNumber) ?? "--")")
                        .font(.caption)
                        .frame(width: 50, alignment: .center)

                    Spacer()
                        .frame(width: 100)

                    Text("\(numberFormatter.string(from: onboardingData.targetHigh as NSNumber) ?? "--")")
                        .font(.caption)
                        .frame(width: 50, alignment: .center)
                }

                Text("These values reflect your personal target range and can be adjusted at any time in the Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding()
    }
}
