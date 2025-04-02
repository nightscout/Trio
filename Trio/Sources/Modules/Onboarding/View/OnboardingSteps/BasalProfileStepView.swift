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
            VStack(alignment: .leading, spacing: 0) {
                // Chart visualization
                if !state.basalProfileItems.isEmpty {
                    VStack(alignment: .leading) {
                        basalProfileChart
                            .frame(height: 180)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(Color.chart.opacity(0.45))
                    .cornerRadius(10)
                }

                TimeValueEditorView(
                    items: $therapyItems,
                    unit: String(localized: "U/hr"),
                    valueOptions: state.basalProfileRateValues
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
                                Text("\(calculateTotalDailyBasal(), specifier: "%.2f")")
                                Text("U/hr")
                                    .foregroundStyle(Color.secondary)
                            }
                            .id(refreshUI) // Erzwingt die Aktualisierung des Totals
                        }
                    }
                    .padding()
                    .background(Color.chart.opacity(0.45))
                    .cornerRadius(10)
                }
            }
        }
        .onAppear {
            if state.basalProfileItems.isEmpty {
                state.addBasalRate()
            }
            therapyItems = state.getBasalTherapyItems(from: state.basalProfileItems)
        }.onChange(of: therapyItems) { _, newItems in
            state.updateBasalRates(from: newItems)
            refreshUI = UUID()
        }
    }

    // Add initial basal rate
    private func addBasalRate() {
        // Default to midnight (00:00) and 1.0 U/h rate
        let timeIndex = state.basalProfileTimeValues.firstIndex { abs($0 - 0) < 1 } ?? 0
        let rateIndex = state.basalProfileRateValues.firstIndex { abs(Double($0) - 1.0) < 0.05 } ?? 20

        let newItem = BasalProfileEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
        state.basalProfileItems.append(newItem)
    }

    // Computed property to check if we can add more basal rates
    private var canAddBasalRate: Bool {
        guard let lastItem = state.basalProfileItems.last else { return true }
        return lastItem.timeIndex < state.basalProfileTimeValues.count - 1
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

    // Chart for visualizing basal profile
    private var basalProfileChart: some View {
        Chart {
            ForEach(Array(state.basalProfileItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = state.basalProfileRateValues[item.rateIndex]

                let tzOffset = TimeZone.current.secondsFromGMT() * -1
                let startDate = Date(timeIntervalSinceReferenceDate: state.basalProfileTimeValues[item.timeIndex])
                    .addingTimeInterval(TimeInterval(tzOffset))
                let endDate = state.basalProfileItems.count > index + 1 ?
                    Date(
                        timeIntervalSinceReferenceDate: state
                            .basalProfileTimeValues[state.basalProfileItems[index + 1].timeIndex]
                    )
                    .addingTimeInterval(TimeInterval(tzOffset)) :
                    Date(timeIntervalSinceReferenceDate: state.basalProfileTimeValues.last!).addingTimeInterval(30 * 60)
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
