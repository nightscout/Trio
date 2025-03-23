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
    @State private var showTimeSelector = false
    @State private var selectedRatioIndex: Int?
    @State private var refreshUI = UUID() // to update chart when slider value changes

    // For chart scaling
    private let chartScale = Calendar.current
        .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
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
                Text("Your carb ratio tells how many grams of carbohydrates one unit of insulin will cover.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                // Chart visualization
                if !state.carbRatioItems.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Carb Ratio Profile")
                            .font(.headline)
                            .padding(.horizontal)

                        carbRatioChart
                            .frame(height: 180)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(10)
                }

                // Carb ratios list
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Carb Ratios")
                            .font(.headline)

                        Spacer()

                        // Add new carb ratio button
                        if state.carbRatioItems.count < 24 {
                            Button(action: {
                                showTimeSelector = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Ratio")
                                }
                                .foregroundColor(.orange)
                            }
                            .disabled(!canAddRatio)
                        }
                    }
                    .padding(.horizontal)

                    // List of carb ratios
                    VStack(spacing: 2) {
                        ForEach(Array(state.carbRatioItems.enumerated()), id: \.element.id) { index, item in
                            HStack {
                                // Time display
                                Text(
                                    dateFormatter
                                        .string(from: Date(
                                            timeIntervalSince1970: state
                                                .carbRatioTimeValues[item.timeIndex]
                                        ))
                                )
                                .frame(width: 80, alignment: .leading)
                                .padding(.leading)

                                // Ratio slider
                                Slider(
                                    value: Binding(
                                        get: {
                                            Double(
                                                truncating: state
                                                    .carbRatioRateValues[item.rateIndex] as NSNumber
                                            ) },
                                        set: { newValue in
                                            // Find closest match in rateValues array
                                            let newIndex = state.carbRatioRateValues
                                                .firstIndex { abs(Double($0) - newValue) < 0.05 } ?? item.rateIndex
                                            state.carbRatioItems[index].rateIndex = newIndex
                                            // Force refresh when slider changes
                                            refreshUI = UUID()
                                        }
                                    ),
                                    in: Double(truncating: state.carbRatioRateValues.first! as NSNumber) ...
                                        Double(truncating: state.carbRatioRateValues.last! as NSNumber),
                                    step: 0.5
                                )
                                .accentColor(.orange)
                                .padding(.horizontal, 5)
                                .onChange(of: state.carbRatioItems[index].rateIndex) { _, _ in
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                }

                                // Display the current value
                                Text(
                                    "\(formatter.string(from: state.carbRatioRateValues[item.rateIndex] as NSNumber) ?? "--") g/U"
                                )
                                .frame(width: 80, alignment: .trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                                // Delete button (not for the first entry at 00:00)
                                if index > 0 {
                                    Button(action: {
                                        state.carbRatioItems.remove(at: index)
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
                            .background(index % 2 == 0 ? Color.orange.opacity(0.05) : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .onAppear {
                        if state.carbRatioItems.isEmpty {
                            state.addCarbRatio()
                        }
                    }
                }

                // Example calculation based on first carb ratio
                if !state.carbRatioItems.isEmpty {
                    Divider()
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example Calculation")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("For 45g of carbs, you would need:")
                                .font(.subheadline)
                                .padding(.horizontal)

                            let insulinNeeded = 45 /
                                Double(
                                    truncating: state
                                        .carbRatioRateValues[state.carbRatioItems.first!.rateIndex] as NSNumber
                                )
                            Text(
                                "45g ÷ \(formatter.string(from: state.carbRatioRateValues[state.carbRatioItems.first!.rateIndex] as NSNumber) ?? "--") = \(String(format: "%.1f", insulinNeeded)) units of insulin"
                            )
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 4)
                    }

                    // Information about the carb ratio
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What This Means")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• A ratio of 10 g/U means 1 unit of insulin covers 10g of carbs")
                            Text("• A lower number means you need more insulin for the same amount of carbs")
                            Text("• A higher number means you need less insulin for the same amount of carbs")
                            Text("• Different times of day may require different ratios")
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
                let timeIndex = state.carbRatioTimeValues.firstIndex { abs($0 - Double(hourInMinutes * 60)) < 10 } ?? 0

                // Check if this hour is already in the profile
                if !state.carbRatioItems.contains(where: { $0.timeIndex == timeIndex }) {
                    buttons.append(.default(Text("\(String(format: "%02d:00", hour))")) {
                        // Get the current ratio from the last item
                        let rateIndex = state.carbRatioItems.last?.rateIndex ?? 0
                        // Create new item with the specified time
                        let newItem = CarbRatioEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
                        // Add the new item and sort the list
                        state.carbRatioItems.append(newItem)
                        state.carbRatioItems.sort(by: { $0.timeIndex < $1.timeIndex })
                    })
                }
            }

            buttons.append(.cancel())

            return ActionSheet(
                title: Text("Select Start Time"),
                message: Text("Choose when this carb ratio should start"),
                buttons: buttons
            )
        }
    }

    // Computed property to check if we can add more carb ratios
    private var canAddRatio: Bool {
        guard let lastItem = state.carbRatioItems.last else { return true }
        return lastItem.timeIndex < state.carbRatioTimeValues.count - 1
    }

    // Chart for visualizing carb ratios
    private var carbRatioChart: some View {
        Chart {
            ForEach(Array(state.carbRatioItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = state.carbRatioRateValues[item.rateIndex]

                let tzOffset = TimeZone.current.secondsFromGMT() * -1
                let startDate = Date(timeIntervalSinceReferenceDate: state.carbRatioTimeValues[item.timeIndex])
                    .addingTimeInterval(TimeInterval(tzOffset))
                let endDate = state.carbRatioItems.count > index + 1 ?
                    Date(
                        timeIntervalSinceReferenceDate: state
                            .carbRatioTimeValues[state.carbRatioItems[index + 1].timeIndex]
                    )
                    .addingTimeInterval(TimeInterval(tzOffset)) :
                    Date(timeIntervalSinceReferenceDate: state.carbRatioTimeValues.last!).addingTimeInterval(30 * 60)
                    .addingTimeInterval(TimeInterval(tzOffset))

                RectangleMark(
                    xStart: .value("start", startDate),
                    xEnd: .value("end", endDate),
                    yStart: .value("rate-start", displayValue),
                    yEnd: .value("rate-end", 0)
                ).foregroundStyle(
                    .linearGradient(
                        colors: [
                            Color.orange.opacity(0.6),
                            Color.orange.opacity(0.1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                ).alignsMarkStylesWithPlotArea()

                LineMark(x: .value("End Date", startDate), y: .value("Ratio", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.orange)

                LineMark(x: .value("Start Date", endDate), y: .value("Ratio", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.orange)
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
