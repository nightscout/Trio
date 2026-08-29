//
//  CarbRatioStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import Charts
import SwiftUI
import UIKit

/// Carb ratio step view for setting insulin-to-carb ratio.
struct CarbRatioStepView: View {
    @Bindable var state: Onboarding.StateModel
    @State private var therapyItems: [TherapySettingsEditor.Item] = []
    @Namespace private var bottomID

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                TherapySettingsEditor.RootView(
                    items: $therapyItems,
                    unit: .gramPerUnit,
                    timeOptions: state.carbRatioTimeValues,
                    valueOptions: state.carbRatioRateValues,
                    validateOnDelete: state.validateCarbRatios,
                    onItemAdded: {
                        withAnimation {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    },
                    chartColor: Color.orange
                )

                // Example calculation based on first carb ratio
                if !state.carbRatioItems.isEmpty {
                    Spacer(minLength: 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example Calculation")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("For 45 g of carbs, you would need:")
                                .font(.subheadline)
                                .padding(.horizontal)

                            let insulinNeeded = 45 /
                                Double(
                                    truncating: state
                                        .carbRatioRateValues[state.carbRatioItems.first!.rateIndex] as NSNumber
                                )
                            Text(
                                "45 \(String(localized: "g", comment: "Gram abbreviation")) / \(formatter.string(from: state.carbRatioRateValues[state.carbRatioItems.first!.rateIndex] as NSNumber) ?? "--") \(String(localized: "g/U")) = \(String(format: "%.1f", insulinNeeded))" +
                                    " " + String(localized: "U", comment: "Insulin unit abbreviation")
                            )
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.chart.opacity(0.65))
                            .cornerRadius(10)
                        }
                    }

                    Spacer(minLength: 20)

                    // Information about the carb ratio
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What This Means")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• A ratio of 10 g/U means 1 unit of insulin covers 10 g of carbs")
                            Text("• A lower number means you need more insulin for the same amount of carbs")
                            Text("• A higher number means you need less insulin for the same amount of carbs")
                            Text("• Different times of day may require different ratios")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    }
                    .id(bottomID)
                }
            }
            .onAppear {
                if state.carbRatioItems.isEmpty {
                    state.addInitialCarbRatio()
                }
                state.validateCarbRatios()
                therapyItems = state.getCarbRatioTherapyItems()
            }.onChange(of: therapyItems) { _, newItems in
                state.updateCarbRatio(from: newItems)
            }
        }
    }
}
