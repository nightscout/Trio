//
//  GlucoseTargetStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import Charts
import SwiftUI
import UIKit

/// Glucose target step view for setting target glucose range.
struct GlucoseTargetStepView: View {
    @State var onboardingData: OnboardingData
    @State private var showUnitPicker = false
    @State private var showTimeSelector = false
    @State private var selectedTargetIndex: Int?
    @State private var showAlert = false
    @State private var errorMessage = ""
    @State private var refreshUI = UUID() // to update chart when slider value changes

    // Formatter for glucose values
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

    // For chart scaling
    private let chartScale = Calendar.current
        .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))

    var body: some View {
        ScrollView {
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
                        let mgdlAction = ActionSheet.Button.default(Text("mg/dL")) {
                            // Store current unit
                            let oldUnit = onboardingData.units
                            // Change to new unit
                            onboardingData.units = .mgdL
                            // Adjust values for unit change, only if unit actually changed
                            if oldUnit != .mgdL {
                                onboardingData.targetLow = max(70, onboardingData.targetLow * 18)
                                onboardingData.targetHigh = max(120, onboardingData.targetHigh * 18)
                                onboardingData.isf = max(30, onboardingData.isf * 18)
                            }
                        }

                        let mmolAction = ActionSheet.Button.default(Text("mmol/L")) {
                            // Store current unit
                            let oldUnit = onboardingData.units
                            // Change to new unit
                            onboardingData.units = .mmolL
                            // Adjust values for unit change, only if unit actually changed
                            if oldUnit != .mmolL {
                                onboardingData.targetLow = max(3.9, onboardingData.targetLow / 18)
                                onboardingData.targetHigh = max(6.7, onboardingData.targetHigh / 18)
                                onboardingData.isf = max(1.7, onboardingData.isf / 18)
                            }
                        }

                        let cancelAction = ActionSheet.Button.cancel()

                        return ActionSheet(
                            title: Text("Select Blood Glucose Units"),
                            buttons: [mgdlAction, mmolAction, cancelAction]
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

                // Chart visualization
                if !onboardingData.targetItems.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Glucose Targets")
                            .font(.headline)
                            .padding(.horizontal)

                        glucoseTargetChart
                            .frame(height: 180)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(10)
                }

                // Glucose target list
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Glucose Targets")
                            .font(.headline)

                        Spacer()

                        // Add new target button
                        if onboardingData.targetItems.count < 24 {
                            Button(action: {
                                showTimeSelector = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Target")
                                }
                                .foregroundColor(.blue)
                            }
                            .disabled(!canAddTarget)
                        }
                    }
                    .padding(.horizontal)

                    // List of targets
                    VStack(spacing: 2) {
                        ForEach(onboardingData.targetItems.indices, id: \.self) { index in
                            let item = onboardingData.targetItems[index]
                            HStack {
                                // Time display
                                Text(
                                    dateFormatter
                                        .string(from: Date(
                                            timeIntervalSince1970: onboardingData
                                                .targetTimeValues[item.timeIndex]
                                        ))
                                )
                                .frame(width: 80, alignment: .leading)
                                .padding(.leading)

                                // Low target slider
                                Slider(
                                    value: Binding(
                                        get: {
                                            Double(
                                                truncating: onboardingData
                                                    .targetRateValues[item.lowIndex] as NSNumber
                                            ) },
                                        set: { newValue in
                                            // Find closest match in rateValues array
                                            let newIndex = onboardingData.targetRateValues
                                                .firstIndex { abs(Double($0) - newValue) < 0.05 } ?? item.lowIndex
                                            onboardingData.targetItems[index].lowIndex = newIndex

                                            // Ensure high target is at least as high as low target
                                            if onboardingData.targetItems[index].highIndex < newIndex {
                                                onboardingData.targetItems[index].highIndex = newIndex
                                            }

                                            // Force refresh when slider changes
                                            refreshUI = UUID()
                                        }
                                    ),
                                    in: Double(truncating: onboardingData.targetRateValues.first! as NSNumber) ...
                                        Double(truncating: onboardingData.targetRateValues.last! as NSNumber),
                                    step: onboardingData.units == .mgdL ? 1 : 0.1
                                )
                                .accentColor(.blue)
                                .padding(.horizontal, 5)
                                .onChange(of: onboardingData.targetItems[index].lowIndex) { _, _ in
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                }

                                // Display the current value
                                Text(
                                    "\(numberFormatter.string(from: onboardingData.targetRateValues[item.lowIndex] as NSNumber) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")"
                                )
                                .frame(width: 80, alignment: .trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                                // Delete button (not for the first entry at 00:00)
                                if index > 0 {
                                    Button(action: {
                                        onboardingData.targetItems.remove(at: index)
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
                            .background(index % 2 == 0 ? Color.blue.opacity(0.05) : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .onAppear {
                        if onboardingData.targetItems.isEmpty {
                            onboardingData.addTarget()
                        }
                    }
                }

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
        .actionSheet(isPresented: $showTimeSelector) {
            var buttons: [ActionSheet.Button] = []

            // Find available time slots in 1-hour increments
            for hour in 0 ..< 24 {
                let hourInMinutes = hour * 60
                // Calculate timeIndex for this hour
                let timeIndex = onboardingData.targetTimeValues.firstIndex { abs($0 - Double(hourInMinutes * 60)) < 10 } ?? 0

                // Check if this hour is already in the profile
                if !onboardingData.targetItems.contains(where: { $0.timeIndex == timeIndex }) {
                    buttons.append(.default(Text("\(String(format: "%02d:00", hour))")) {
                        // Get the current low and high values from the last item
                        let lowIndex = onboardingData.targetItems.last?.lowIndex ?? 0
                        let highIndex = onboardingData.targetItems.last?.highIndex ?? lowIndex

                        // Create new item with the specified time
                        let newItem = TargetsEditor.Item(lowIndex: lowIndex, highIndex: highIndex, timeIndex: timeIndex)

                        // Add the new item and sort the list by timeIndex
                        onboardingData.targetItems.append(newItem)
                        onboardingData.targetItems.sort(by: { $0.timeIndex < $1.timeIndex })
                    })
                }
            }

            buttons.append(.cancel())

            return ActionSheet(
                title: Text("Select Start Time"),
                message: Text("Choose when this target should start"),
                buttons: buttons
            )
        }
    }

    // Computed property to check if we can add more targets
    private var canAddTarget: Bool {
        guard let lastItem = onboardingData.targetItems.last else { return true }
        return lastItem.timeIndex < onboardingData.targetTimeValues.count - 1
    }

    // Chart for visualizing glucose targets
    private var glucoseTargetChart: some View {
        Chart {
            ForEach(Array(onboardingData.targetItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = onboardingData.targetRateValues[item.lowIndex]

                let tzOffset = TimeZone.current.secondsFromGMT() * -1
                let startDate = Date(timeIntervalSinceReferenceDate: onboardingData.targetTimeValues[item.timeIndex])
                    .addingTimeInterval(TimeInterval(tzOffset))
                let endDate = onboardingData.targetItems.count > index + 1 ?
                    Date(
                        timeIntervalSinceReferenceDate: onboardingData
                            .targetTimeValues[onboardingData.targetItems[index + 1].timeIndex]
                    )
                    .addingTimeInterval(TimeInterval(tzOffset)) :
                    Date(timeIntervalSinceReferenceDate: onboardingData.targetTimeValues.last!).addingTimeInterval(30 * 60)
                    .addingTimeInterval(TimeInterval(tzOffset))

                RectangleMark(
                    xStart: .value("start", startDate),
                    xEnd: .value("end", endDate),
                    yStart: .value("rate-start", displayValue),
                    yEnd: .value("rate-end", 0)
                ).foregroundStyle(
                    .linearGradient(
                        colors: [
                            Color.green.opacity(0.6),
                            Color.green.opacity(0.1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                ).alignsMarkStylesWithPlotArea()

                LineMark(x: .value("End Date", startDate), y: .value("Ratio", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.green)

                LineMark(x: .value("Start Date", endDate), y: .value("Ratio", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.green)
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
