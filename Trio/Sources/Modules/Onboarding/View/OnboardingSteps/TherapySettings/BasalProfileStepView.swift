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
    @State private var therapyItems: [TherapySettingItem] = []
    @Namespace private var bottomID

    private var rateFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                TherapySettingEditorView(
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
                    chartColor: Color.purple
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
                                Text(rateFormatter.string(from: calculateTotalDailyBasal() as NSNumber) ?? "0")
                                Text("U/day")
                                    .foregroundStyle(Color.secondary)
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

    // Calculate the total daily basal insulin
    private func calculateTotalDailyBasal() -> Double {
        let items = state.basalProfileItems

        // If there are no items, return 0
        if items.isEmpty {
            return 0.0
        }

        var total: Double = 0.0

        // Safely create profile items with proper error checking
        let profileItems = items.compactMap { item -> (timeIndex: Int, rate: Decimal)? in
            // Safety check - make sure indices are within bounds
            guard item.timeIndex >= 0 && item.timeIndex < state.basalProfileTimeValues.count,
                  item.rateIndex >= 0 && item.rateIndex < state.basalProfileRateValues.count
            else {
                return nil
            }

            let timeValue = state.basalProfileTimeValues[item.timeIndex]
            let rate = state.basalProfileRateValues[item.rateIndex]
            return (Int(timeValue / 60), rate)
        }.sorted(by: { $0.timeIndex < $1.timeIndex })

        // If after safety checks we have no valid items, return 0
        if profileItems.isEmpty {
            return 0.0
        }

        // Create time points array safely
        var timePoints = profileItems.map(\.timeIndex)

        // Add the 24-hour mark to complete the cycle
        timePoints.append(24 * 60) // Add 24 hours in minutes

        // Calculate the total by multiplying each rate by its duration
        for i in 0 ..< profileItems.count {
            let rate = profileItems[i].rate
            let currentTimeIndex = profileItems[i].timeIndex

            // Calculate duration safely
            let nextTimeIndex = i + 1 < timePoints.count ? timePoints[i + 1] : (24 * 60)
            let duration = nextTimeIndex - currentTimeIndex

            // Only add if duration is positive
            if duration > 0 {
                total += Double(rate) * Double(duration) / 60.0 // Convert to hours
            }
        }

        return total
    }
}
