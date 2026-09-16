//
//  BasalProfileStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import Charts
import SwiftUI
import UIKit

/// Basal profile step view for setting basal insulin rates.
struct BasalProfileStepView: View {
    @Bindable var state: Onboarding.StateModel
    @State private var refreshUI = UUID() // to update chart when slider value changes
    @State private var therapyItems: [TherapySettingsEditor.Item] = []
    @Namespace private var bottomID

    private var rateFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                TherapySettingsEditor.EditingView(
                    items: $therapyItems,
                    unit: .unitPerHour,
                    timeOptions: state.basalProfileTimeValues,
                    valueOptions: state.basalProfileRateValues,
                    validateOnDelete: state.validateBasal,
                    onItemAdded: {
                        withAnimation {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    },
                    chartColor: Color.purple,
                    chartAccessibilityLabel: String(localized: "Basal rate profile chart, 24 hours")
                )

                Spacer(minLength: 20)

                // Total daily basal calculation
                if !state.basalProfileItems.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Total")
                                .bold()

                            Spacer()

                            HStack {
                                Text("Total")
                                    .bold()

                                Spacer()

                                HStack {
                                    Text(rateFormatter.string(from: state.totalDailyBasal() as NSNumber) ?? "0")
                                    Text("U/day")
                                        .foregroundStyle(Color.secondary)
                                }
                                .id(refreshUI) // Erzwingt die Aktualisierung des Totals
                            }
                            .id(refreshUI) // Erzwingt die Aktualisierung des Totals
                        }
                    }
                    .padding()
                    .background(Color.chart.opacity(0.65))
                    .cornerRadius(10)
                    .id(bottomID)
                }
            }
            .onAppear {
                if state.basalProfileItems.isEmpty {
                    state.addInitialBasalRate()
                }
                state.validateBasal()
                therapyItems = state.getBasalTherapyItems()
            }.onChange(of: therapyItems) { _, newItems in
                state.updateBasal(from: newItems)
                refreshUI = UUID()
            }
        }
    }
}
