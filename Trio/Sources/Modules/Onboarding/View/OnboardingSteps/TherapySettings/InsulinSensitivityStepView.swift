//
//  InsulinSensitivityStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import Charts
import SwiftUI
import UIKit

/// Insulin sensitivity step view for setting insulin sensitivity factor.
struct InsulinSensitivityStepView: View {
    @Bindable var state: Onboarding.StateModel
    @State private var therapyItems: [TherapySettingsEditor.Item] = []
    @Namespace private var bottomID

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = state.units == .mmolL ? 1 : 0
        return formatter
    }

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                TherapySettingsEditor.RootView(
                    items: $therapyItems,
                    unit: state.units == .mgdL ? .mgdLPerUnit : .mmolLPerUnit,
                    timeOptions: state.isfTimeValues,
                    valueOptions: state.isfRateValues,
                    validateOnDelete: state.validateISF,
                    onItemAdded: {
                        withAnimation {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    },
                    chartColor: Color.cyan,
                    chartDisplayValueSelector: { state.units == .mgdL ? $0.value : $0.value.asMmolL }
                )

                // Example calculation based on first ISF
                if !state.isfItems.isEmpty {
                    Spacer(minLength: 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example Calculation")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            // Current glucose is 40 mg/dL or 2.2 mmol/L above target
                            let aboveTarget = state.units == .mgdL ? Decimal(40) : 40.asMmolL
                            let firstIsfRate: Decimal = state.isfRateValues[state.isfItems.first?.rateIndex ?? 0]
                            let isfValue = state.units == .mgdL ? firstIsfRate : firstIsfRate.asMmolL
                            let insulinNeeded = aboveTarget / isfValue

                            Text(
                                "If you are \(numberFormatter.string(from: aboveTarget as NSNumber) ?? "--") \(state.units.rawValue) above target:"
                            )
                            .font(.subheadline)
                            .padding(.horizontal)

                            Text(
                                "\(aboveTarget.description) \(state.units.rawValue) / \(isfValue.description) \(state.units.rawValue)/\(String(localized: "U", comment: "Insulin unit abbreviation")) = \(String(format: "%.1f", Double(insulinNeeded))) \(String(localized: "U", comment: "Insulin unit abbreviation"))"
                            )
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.chart.opacity(0.65))
                            .cornerRadius(10)
                        }
                    }

                    Spacer(minLength: 20)

                    // Information about ISF
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What This Means")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 4) {
                            let isfValue = "\(state.units == .mgdL ? Decimal(50) : 50.asMmolL)"
                            Text(
                                "• An ISF of \(isfValue) \(state.units.rawValue)/U means 1 U lowers your glucose by \(isfValue) \(state.units.rawValue)"
                            )
                            Text("• A lower number means you're less sensitive (more resistant) to insulin")
                            Text("• A higher number means you're more sensitive (less resistant) to insulin")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    }
                    .id(bottomID)
                }
            }
            .onAppear {
                if state.isfItems.isEmpty {
                    state.addInitialISF()
                }
                state.validateISF()
                therapyItems = state.getISFTherapyItems()
            }.onChange(of: therapyItems) { _, newItems in
                state.updateISF(from: newItems)
            }
        }
    }
}
