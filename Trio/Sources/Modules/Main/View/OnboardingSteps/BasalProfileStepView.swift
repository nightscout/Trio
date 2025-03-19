//
//  BasalProfileStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import SwiftUI

/// Basal profile step view for setting basal insulin rates.
struct BasalProfileStepView: View {
    @State var onboardingData: OnboardingData
    @State private var showTimeSelector = false
    @State private var selectedBasalIndex: Int?
    @State private var newStartTime: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your basal insulin profile determines how much background insulin you receive throughout the day.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Basal rates list
            VStack(alignment: .leading, spacing: 10) {
                Text("Basal Rates")
                    .font(.headline)

                ForEach(Array(onboardingData.basalRates.enumerated()), id: \.element.id) { index, basalRate in
                    HStack {
                        Text(basalRate.timeFormatted)
                            .frame(width: 80, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { Double(truncating: onboardingData.basalRates[index].rate as NSNumber) },
                                set: { onboardingData.basalRates[index].rate = Decimal($0) }
                            ),
                            in: 0 ... 5,
                            step: 0.05
                        )
                        .accentColor(.purple)

                        Text("\(String(format: "%.2f", Double(truncating: basalRate.rate as NSNumber))) U/h")
                            .frame(width: 70, alignment: .trailing)

                        // Delete button (not for the first entry at 00:00)
                        if index > 0 {
                            Button(action: {
                                onboardingData.basalRates.remove(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                }
            }

            // Add new basal rate button
            if onboardingData.basalRates.count < 24 {
                Button(action: {
                    showTimeSelector = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Basal Rate")
                    }
                    .foregroundColor(.purple)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Basal profile visualization
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Basal Profile")
                    .font(.headline)

                // Simple chart representation
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0 ..< 24) { hour in
                        let rate = basalRateAt(hour: hour)
                        let height = min(120, CGFloat(Double(rate) * 30))

                        VStack {
                            Rectangle()
                                .fill(Color.purple.opacity(0.7))
                                .frame(width: 10, height: height)

                            if hour % 6 == 0 {
                                Text("\(hour):00")
                                    .font(.system(size: 8))
                                    .frame(width: 20)
                                    .rotationEffect(.degrees(-45))
                                    .offset(y: 10)
                            }
                        }
                    }
                }
                .frame(height: 150)
                .padding(.top)

                Text("This chart shows your basal insulin delivery throughout a 24-hour day.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .actionSheet(isPresented: $showTimeSelector) {
            var buttons: [ActionSheet.Button] = []

            // Find available time slots in 1-hour increments
            for hour in 1 ..< 24 {
                let hourInMinutes = hour * 60
                // Check if this hour is already in the profile
                if !onboardingData.basalRates.contains(where: { $0.startTime == hourInMinutes }) {
                    buttons.append(.default(Text("\(String(format: "%02d:00", hour))")) {
                        // Get the current basal rate active at this time
                        let rate = basalRateAt(hour: hour)
                        // Add new basal rate with the same value
                        onboardingData.basalRates.append(
                            OnboardingData.BasalRateEntry(startTime: hourInMinutes, rate: rate)
                        )
                        // Sort basal rates by time
                        onboardingData.basalRates.sort(by: { $0.startTime < $1.startTime })
                    })
                }
            }

            buttons.append(.cancel())

            return ActionSheet(
                title: Text("Select Start Time"),
                message: Text("Choose when this basal rate should start"),
                buttons: buttons
            )
        }
    }

    /// Calculates the basal rate at a specific hour based on the profile.
    private func basalRateAt(hour: Int) -> Decimal {
        let minutes = hour * 60
        // Find the most recent basal rate entry that starts before or at the given hour
        let applicableRate = onboardingData.basalRates
            .filter { $0.startTime <= minutes }
            .sorted(by: { $0.startTime > $1.startTime })
            .first

        return applicableRate?.rate ?? Decimal(1.0)
    }
}
