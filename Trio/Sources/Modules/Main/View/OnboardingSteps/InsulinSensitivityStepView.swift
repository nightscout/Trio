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
    @State var onboardingData: OnboardingData
    @State private var showTimeSelector = false
    @State private var selectedISFIndex: Int?
    @State private var showAlert = false
    @State private var errorMessage = ""
    @State private var refreshUI = UUID() // to update chart when slider value changes

    // For chart scaling
    private let chartScale = Calendar.current
        .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = onboardingData.units == .mmolL ? 1 : 0
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
                Text(
                    "Your insulin sensitivity factor (ISF) indicates how much one unit of insulin will lower your blood glucose."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)

                // Chart visualization
                if !onboardingData.isfItems.isEmpty {
                    VStack(alignment: .leading) {
                        Text("ISF Profile")
                            .font(.headline)
                            .padding(.horizontal)

                        isfChart
                            .frame(height: 180)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.05))
                    .cornerRadius(10)
                }

                // ISF values list
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Sensitivity Factors")
                            .font(.headline)

                        Spacer()

                        // Add new ISF button
                        if onboardingData.isfItems.count < 24 {
                            Button(action: {
                                showTimeSelector = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add ISF")
                                }
                                .foregroundColor(.red)
                            }
                            .disabled(!canAddISF)
                        }
                    }
                    .padding(.horizontal)

                    if onboardingData.isfItems.isEmpty {
                        // Add default entry if no items exist
                        Button("Add Initial ISF Value") {
                            onboardingData.addISFValue()
                        }
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    } else {
                        // List of ISF values
                        VStack(spacing: 2) {
                            ForEach(Array(onboardingData.isfItems.enumerated()), id: \.element.id) { index, item in
                                HStack {
                                    // Time display
                                    Text(
                                        dateFormatter
                                            .string(from: Date(
                                                timeIntervalSince1970: onboardingData
                                                    .isfTimeValues[item.timeIndex]
                                            ))
                                    )
                                    .frame(width: 80, alignment: .leading)
                                    .padding(.leading)

                                    // ISF slider
                                    Slider(
                                        value: Binding(
                                            get: {
                                                guard !onboardingData.rateValues.isEmpty,
                                                      item.rateIndex < onboardingData.rateValues.count
                                                else {
                                                    return 0.0
                                                }
                                                return Double(
                                                    truncating: onboardingData
                                                        .rateValues[item.rateIndex] as NSNumber
                                                )
                                            },
                                            set: { newValue in
                                                guard !onboardingData.rateValues.isEmpty else { return }

                                                // Find closest match in rateValues array
                                                let newIndex = onboardingData.rateValues
                                                    .firstIndex { abs(Double($0) - newValue) < 0.5 } ?? item.rateIndex

                                                // Ensure index is valid before updating
                                                if newIndex < onboardingData.rateValues.count,
                                                   index < onboardingData.isfItems.count
                                                {
                                                    onboardingData.isfItems[index].rateIndex = newIndex
                                                    // Force refresh when slider changes
                                                    refreshUI = UUID()
                                                }
                                            }
                                        ),
                                        in: onboardingData.rateValues.isEmpty ? 0 ... 1 :
                                            Double(truncating: onboardingData.rateValues.first! as NSNumber) ...
                                            Double(truncating: onboardingData.rateValues.last! as NSNumber),
                                        step: onboardingData.units == .mgdL ? 1 : 0.1
                                    )
                                    .accentColor(.red)
                                    .padding(.horizontal, 5)
                                    .onChange(of: onboardingData.isfItems[index].rateIndex) { _, _ in
                                        // Trigger immediate UI update when slider value changes
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                    }

                                    // Display the current value
                                    Text(
                                        "\(onboardingData.rateValues.isEmpty || item.rateIndex >= onboardingData.rateValues.count ? "--" : numberFormatter.string(from: onboardingData.rateValues[item.rateIndex] as NSNumber) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")"
                                    )
                                    .frame(width: 90, alignment: .trailing)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                    // Delete button (not for the first entry at 00:00)
                                    if index > 0 {
                                        Button(action: {
                                            onboardingData.isfItems.remove(at: index)
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
                                .background(index % 2 == 0 ? Color.red.opacity(0.05) : Color.clear)
                                .cornerRadius(8)
                            }
                        }
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                }

                // Example calculation based on first ISF
                if !onboardingData.isfItems.isEmpty {
                    Divider()
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example Calculation")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 4) {
                            // Current glucose is 40 mg/dL or 2.2 mmol/L above target
                            let aboveTarget = onboardingData.units == .mgdL ? 40.0 : 2.2

                            let isfValue = onboardingData.rateValues.isEmpty || onboardingData.isfItems.isEmpty ?
                                Double(truncating: onboardingData.isf as NSNumber) :
                                Double(
                                    truncating: onboardingData
                                        .rateValues[onboardingData.isfItems.first!.rateIndex] as NSNumber
                                )

                            let insulinNeeded = aboveTarget / isfValue

                            Text(
                                "If you are \(numberFormatter.string(from: NSNumber(value: aboveTarget)) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L") above target:"
                            )
                            .font(.subheadline)
                            .padding(.horizontal)

                            Text(
                                "\(numberFormatter.string(from: NSNumber(value: aboveTarget)) ?? "--") ÷ \(numberFormatter.string(from: isfValue as NSNumber) ?? "--") = \(String(format: "%.1f", insulinNeeded)) units of insulin"
                            )
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 4)
                    }

                    // Information about ISF
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What This Means")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 4) {
                            if onboardingData.units == .mgdL {
                                Text("• An ISF of 50 mg/dL means 1 unit of insulin lowers your BG by 50 mg/dL")
                                Text("• A lower number means you're more sensitive to insulin")
                                Text("• A higher number means you're less sensitive to insulin")
                                Text("• ISF may vary throughout the day")
                            } else {
                                Text("• An ISF of 2.8 mmol/L means 1 unit of insulin lowers your BG by 2.8 mmol/L")
                                Text("• A lower number means you're more sensitive to insulin")
                                Text("• A higher number means you're less sensitive to insulin")
                                Text("• ISF may vary throughout the day")
                            }
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
                let timeIndex = onboardingData.isfTimeValues
                    .firstIndex { abs($0 - Double(hourInMinutes * 60)) < 10 } ?? 0

                // Check if this hour is already in the profile
                if !onboardingData.isfItems.contains(where: { $0.timeIndex == timeIndex }) {
                    buttons.append(.default(Text("\(String(format: "%02d:00", hour))")) {
                        // Get the current rate from the last item
                        let rateIndex = onboardingData.isfItems.last?.rateIndex ?? 45 // Default to 45 mg/dL
                        // Create new item with the specified time
                        let newItem = ISFEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
                        // Add the new item and sort the list
                        onboardingData.isfItems.append(newItem)
                        onboardingData.isfItems.sort(by: { $0.timeIndex < $1.timeIndex })
                    })
                }
            }

            buttons.append(.cancel())

            return ActionSheet(
                title: Text("Select Start Time"),
                message: Text("Choose when this sensitivity factor should start"),
                buttons: buttons
            )
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Unable to Save ISF Profile"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // Add initial ISF value
    private func addInitialISF() {
        // Default to midnight (00:00) and 50 mg/dL (or 2.8 mmol/L)
        let timeIndex = onboardingData.isfTimeValues.firstIndex { abs($0 - 0) < 1 } ?? 0
        let defaultISF = onboardingData.units == .mgdL ? 50.0 : 2.8
        let rateIndex = onboardingData.rateValues.firstIndex { abs(Double($0) - defaultISF) < 0.5 } ?? 45

        let newItem = ISFEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
        onboardingData.isfItems.append(newItem)
    }

    // Computed property to check if we can add more ISF values
    private var canAddISF: Bool {
        guard let lastItem = onboardingData.isfItems.last else { return true }
        return lastItem.timeIndex < onboardingData.isfTimeValues.count - 1
    }

    // Chart for visualizing ISF profile
    private var isfChart: some View {
        Chart {
            ForEach(Array(onboardingData.isfItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = onboardingData.rateValues[item.rateIndex]

                let tzOffset = TimeZone.current.secondsFromGMT() * -1
                let startDate = Date(timeIntervalSinceReferenceDate: onboardingData.isfTimeValues[item.timeIndex])
                    .addingTimeInterval(TimeInterval(tzOffset))
                let endDate = onboardingData.isfItems.count > index + 1 ?
                    Date(
                        timeIntervalSinceReferenceDate: onboardingData
                            .isfTimeValues[onboardingData.isfItems[index + 1].timeIndex]
                    )
                    .addingTimeInterval(TimeInterval(tzOffset)) :
                    Date(timeIntervalSinceReferenceDate: onboardingData.isfTimeValues.last!).addingTimeInterval(30 * 60)
                    .addingTimeInterval(TimeInterval(tzOffset))

                RectangleMark(
                    xStart: .value("start", startDate),
                    xEnd: .value("end", endDate),
                    yStart: .value("rate-start", displayValue),
                    yEnd: .value("rate-end", 0)
                ).foregroundStyle(
                    .linearGradient(
                        colors: [
                            Color.red.opacity(0.6),
                            Color.red.opacity(0.1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                ).alignsMarkStylesWithPlotArea()

                LineMark(x: .value("End Date", startDate), y: .value("ISF", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.red)

                LineMark(x: .value("Start Date", endDate), y: .value("ISF", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.red)
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
