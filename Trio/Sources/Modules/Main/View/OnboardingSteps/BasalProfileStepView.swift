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
    @State var onboardingData: OnboardingData
    @State private var showTimeSelector = false
    @State private var selectedBasalIndex: Int?
    @State private var showAlert = false
    @State private var errorMessage = ""
    @State private var refreshUI = UUID() // to update chart when slider value changes

    // For chart scaling
    private let chartScale = Calendar.current
        .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your basal insulin profile determines how much background insulin you receive throughout the day.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                // Chart visualization
                if !onboardingData.basalProfileItems.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Basal Profile")
                            .font(.headline)
                            .padding(.horizontal)

                        basalProfileChart
                            .frame(height: 180)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 5)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(10)
                }

                // Basal rates list
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Basal Rates")
                            .font(.headline)

                        Spacer()

                        // Add new basal rate button
                        if onboardingData.basalProfileItems.count < 24 {
                            Button(action: {
                                showTimeSelector = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Rate")
                                }
                                .foregroundColor(.purple)
                            }
                            .disabled(!canAddBasalRate)
                        }
                    }
                    .padding(.horizontal)

                    // List of basal rates
                    VStack(spacing: 2) {
                        ForEach(Array(onboardingData.basalProfileItems.enumerated()), id: \.element.id) { index, item in
                            HStack {
                                // Time display
                                Text(
                                    dateFormatter
                                        .string(from: Date(
                                            timeIntervalSince1970: onboardingData
                                                .basalProfileTimeValues[item.timeIndex]
                                        ))
                                )
                                .frame(width: 80, alignment: .leading)
                                .padding(.leading)

                                // Rate slider
                                Slider(
                                    value: Binding(
                                        get: {
                                            guard !onboardingData.basalProfileRateValues.isEmpty,
                                                  item.rateIndex < onboardingData.basalProfileRateValues.count
                                            else {
                                                return 0.0
                                            }
                                            return Double(
                                                truncating: onboardingData
                                                    .basalProfileRateValues[item.rateIndex] as NSNumber
                                            )
                                        },
                                        set: { newValue in
                                            guard !onboardingData.basalProfileRateValues.isEmpty else { return }

                                            // Find closest match in rateValues array
                                            let newIndex = onboardingData.basalProfileRateValues
                                                .firstIndex { abs(Double($0) - newValue) < 0.005 } ?? item.rateIndex

                                            // Ensure index is valid before updating
                                            if newIndex < onboardingData.basalProfileRateValues.count,
                                               index < onboardingData.basalProfileItems.count
                                            {
                                                onboardingData.basalProfileItems[index].rateIndex = newIndex
                                                // Force refresh when slider changes
                                                refreshUI = UUID()
                                            }
                                        }
                                    ),
                                    in: onboardingData.basalProfileRateValues.isEmpty ? 0 ... 1 :
                                        Double(truncating: onboardingData.basalProfileRateValues.first! as NSNumber) ...
                                        Double(truncating: onboardingData.basalProfileRateValues.last! as NSNumber),
                                    step: 0.05
                                )
                                .accentColor(.purple)
                                .padding(.horizontal, 5)
                                .onChange(of: onboardingData.basalProfileItems[index].rateIndex) { _, _ in
                                    // Trigger immediate UI update when slider value changes
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                }

                                // Display the current value
                                Text(
                                    "\(onboardingData.basalProfileRateValues.isEmpty || item.rateIndex >= onboardingData.basalProfileRateValues.count ? "--" : formatter.string(from: onboardingData.basalProfileRateValues[item.rateIndex] as NSNumber) ?? "--") U/h"
                                )
                                .frame(width: 80, alignment: .trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                                // Delete button (not for the first entry at 00:00)
                                if index > 0 {
                                    Button(action: {
                                        onboardingData.basalProfileItems.remove(at: index)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 5)
                                    }
                                } else {
                                    // Spacer to maintain alignment
                                    Spacer()
                                        .frame(width: 30)
                                }
                            }
                            .padding(.vertical, 12)
                            .background(index % 2 == 0 ? Color.purple.opacity(0.05) : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .onAppear {
                        addBasalRate()
                    }
                }

                // Total daily basal calculation
                if !onboardingData.basalProfileItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Total Daily Basal")
                                .font(.headline)
                                .padding(.horizontal)

                            Spacer()

                            Text("\(calculateTotalDailyBasal(), specifier: "%.2f") U/day")
                                .font(.headline)
                                .padding(.horizontal)
                                .id(refreshUI) // Erzwingt die Aktualisierung des Totals
                        }
                    }
                    .padding(.top)

                    // Information about basal rates
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What This Means")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• The basal profile provides background insulin throughout the day")
                            Text("• Rates should be adjusted based on your body's varying insulin needs")
                            Text("• Morning hours may require more insulin due to 'dawn phenomenon'")
                            Text("• Lower rates are typically needed during sleep or periods of activity")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .actionSheet(isPresented: $showTimeSelector) {
            var buttons: [ActionSheet.Button] = []

            // Find available time slots in 1-hour increments
            for hour in 0 ..< 24 {
                let hourInMinutes = hour * 60
                // Calculate timeIndex for this hour
                let timeIndex = onboardingData.basalProfileTimeValues
                    .firstIndex { abs($0 - Double(hourInMinutes * 60)) < 10 } ?? 0

                // Check if this hour is already in the profile
                if !onboardingData.basalProfileItems.contains(where: { $0.timeIndex == timeIndex }) {
                    buttons.append(.default(Text("\(String(format: "%02d:00", hour))")) {
                        // Get the current rate from the last item
                        let rateIndex = onboardingData.basalProfileItems.last?.rateIndex ?? 20 // 1.0 U/h as default
                        // Create new item with the specified time
                        let newItem = BasalProfileEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
                        // Add the new item and sort the list
                        onboardingData.basalProfileItems.append(newItem)
                        onboardingData.basalProfileItems.sort(by: { $0.timeIndex < $1.timeIndex })
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
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Unable to Save Basal Profile"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // Add initial basal rate
    private func addBasalRate() {
        // Default to midnight (00:00) and 1.0 U/h rate
        let timeIndex = onboardingData.basalProfileTimeValues.firstIndex { abs($0 - 0) < 1 } ?? 0
        let rateIndex = onboardingData.basalProfileRateValues.firstIndex { abs(Double($0) - 1.0) < 0.05 } ?? 20

        let newItem = BasalProfileEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
        onboardingData.basalProfileItems.append(newItem)
    }

    // Computed property to check if we can add more basal rates
    private var canAddBasalRate: Bool {
        guard let lastItem = onboardingData.basalProfileItems.last else { return true }
        return lastItem.timeIndex < onboardingData.basalProfileTimeValues.count - 1
    }

    // Calculate the total daily basal insulin
    private func calculateTotalDailyBasal() -> Double {
        let items = onboardingData.basalProfileItems

        // If there are no items, return 0
        if items.isEmpty {
            return 0.0
        }

        var total: Double = 0.0

        // Safely create profile items with proper error checking
        let profileItems = items.compactMap { item -> (timeIndex: Int, rate: Decimal)? in
            // Safety check - make sure indices are within bounds
            guard item.timeIndex >= 0 && item.timeIndex < onboardingData.basalProfileTimeValues.count,
                  item.rateIndex >= 0 && item.rateIndex < onboardingData.basalProfileRateValues.count
            else {
                return nil
            }

            let timeValue = onboardingData.basalProfileTimeValues[item.timeIndex]
            let rate = onboardingData.basalProfileRateValues[item.rateIndex]
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

    // Chart for visualizing basal profile
    private var basalProfileChart: some View {
        Chart {
            ForEach(Array(onboardingData.basalProfileItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = onboardingData.basalProfileRateValues[item.rateIndex]

                let tzOffset = TimeZone.current.secondsFromGMT() * -1
                let startDate = Date(timeIntervalSinceReferenceDate: onboardingData.basalProfileTimeValues[item.timeIndex])
                    .addingTimeInterval(TimeInterval(tzOffset))
                let endDate = onboardingData.basalProfileItems.count > index + 1 ?
                    Date(
                        timeIntervalSinceReferenceDate: onboardingData
                            .basalProfileTimeValues[onboardingData.basalProfileItems[index + 1].timeIndex]
                    )
                    .addingTimeInterval(TimeInterval(tzOffset)) :
                    Date(timeIntervalSinceReferenceDate: onboardingData.basalProfileTimeValues.last!).addingTimeInterval(30 * 60)
                    .addingTimeInterval(TimeInterval(tzOffset))

                RectangleMark(
                    xStart: .value("start", startDate),
                    xEnd: .value("end", endDate),
                    yStart: .value("rate-start", displayValue),
                    yEnd: .value("rate-end", 0)
                ).foregroundStyle(
                    .linearGradient(
                        colors: [
                            Color.purple.opacity(0.6),
                            Color.purple.opacity(0.1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                ).alignsMarkStylesWithPlotArea()

                LineMark(x: .value("End Date", startDate), y: .value("Rate", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.purple)

                LineMark(x: .value("Start Date", endDate), y: .value("Rate", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.purple)
            }
        }
        .id(refreshUI) // Force chart update
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour())
                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        .chartXScale(
            domain: Calendar.current.startOfDay(for: chartScale!) ... Calendar.current.startOfDay(for: chartScale!)
                .addingTimeInterval(60 * 60 * 24)
        )
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
    }
}
