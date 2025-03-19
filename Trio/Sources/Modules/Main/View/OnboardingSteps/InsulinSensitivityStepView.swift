//
//  InsulinSensitivityStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import SwiftUI

/// Insulin sensitivity step view for setting insulin sensitivity factor.
struct InsulinSensitivityStepView: View {
    @State var onboardingData: OnboardingData

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = onboardingData.units == .mmolL ? 1 : 0
        return formatter
    }

    private var ispRange: ClosedRange<Double> {
        if onboardingData.units == .mgdL {
            return 10 ... 100
        } else {
            return 0.5 ... 5.5
        }
    }

    private var ispStep: Double {
        onboardingData.units == .mgdL ? 1 : 0.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your insulin sensitivity factor (ISF) indicates how much one unit of insulin will lower your blood glucose.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Insulin Sensitivity Factor")
                    .font(.headline)

                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(truncating: onboardingData.isf as NSNumber) },
                            set: { onboardingData.isf = Decimal($0) }
                        ),
                        in: ispRange,
                        step: ispStep
                    )
                    .accentColor(.red)

                    // Display the current value
                    Text(
                        "\(numberFormatter.string(from: onboardingData.isf as NSNumber) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")"
                    )
                    .frame(width: 80, alignment: .trailing)
                }

                // Example calculation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example Calculation")
                        .font(.headline)
                        .padding(.top)

                    VStack(alignment: .leading, spacing: 4) {
                        // Current glucose is 40 mg/dL or 2.2 mmol/L above target
                        let aboveTarget = onboardingData.units == .mgdL ? 40.0 : 2.2
                        let insulinNeeded = aboveTarget / Double(truncating: onboardingData.isf as NSNumber)

                        Text(
                            "If you are \(numberFormatter.string(from: NSNumber(value: aboveTarget)) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L") above target:"
                        )
                        .font(.subheadline)

                        Text(
                            "\(numberFormatter.string(from: NSNumber(value: aboveTarget)) ?? "--") ÷ \(numberFormatter.string(from: onboardingData.isf as NSNumber) ?? "--") = \(String(format: "%.1f", insulinNeeded)) units of insulin"
                        )
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding(.vertical, 4)

                    // Information about ISF
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What This Means")
                            .font(.headline)
                            .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 4) {
                            if onboardingData.units == .mgdL {
                                Text("• An ISF of 50 mg/dL means 1 unit of insulin lowers your BG by 50 mg/dL")
                                Text("• A lower number means you're more sensitive to insulin")
                                Text("• A higher number means you're less sensitive to insulin")
                            } else {
                                Text("• An ISF of 2.8 mmol/L means 1 unit of insulin lowers your BG by 2.8 mmol/L")
                                Text("• A lower number means you're more sensitive to insulin")
                                Text("• A higher number means you're less sensitive to insulin")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }

            // Visualization of ISF
            VStack(alignment: .leading, spacing: 8) {
                Text("Visual Reference")
                    .font(.headline)
                    .padding(.top)

                HStack(spacing: 20) {
                    VStack {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        Text("1U")
                            .font(.headline)
                        Text("Insulin")
                            .font(.caption)
                    }

                    Text("⟹")
                        .font(.title)

                    VStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)
                        Text("\(numberFormatter.string(from: onboardingData.isf as NSNumber) ?? "--")")
                            .font(.headline)
                        Text(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding()
    }
}
