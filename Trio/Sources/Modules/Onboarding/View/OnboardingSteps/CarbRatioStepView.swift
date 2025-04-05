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
    @State private var refreshUI = UUID() // to update chart when slider value changes
    @State private var therapyItems: [TherapySettingItem] = []
    @State private var now = Date()

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
        LazyVStack {
            VStack(alignment: .leading, spacing: 0) {
                // Chart visualization
                if !state.carbRatioItems.isEmpty {
                    VStack(alignment: .leading) {
                        carbRatioChart
                            .frame(height: 180)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(Color.chart.opacity(0.65))
                    .clipShape(
                        .rect(
                            topLeadingRadius: 10,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 10
                        )
                    )
                }

                TherapySettingEditorView(
                    items: $therapyItems,
                    unit: .gramPerUnit,
                    timeOptions: state.carbRatioTimeValues,
                    valueOptions: state.carbRatioRateValues,
                    validateOnDelete: state.validateCarbRatios
                )

                // Example calculation based on first carb ratio
                if !state.carbRatioItems.isEmpty {
                    Spacer(minLength: 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example Calculation")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("For 45g of carbs, you would need:")
                                .font(.subheadline)
                                .padding(.horizontal)

                            let insulinNeeded = 45 /
                                Double(
                                    truncating: state
                                        .carbRatioRateValues[state.carbRatioItems.first!.rateIndex] as NSNumber
                                )
                            Text(
                                "45 \(String(localized: "g", comment: "Gram abbreviation")) / \(formatter.string(from: state.carbRatioRateValues[state.carbRatioItems.first!.rateIndex] as NSNumber) ?? "--")  = \(String(format: "%.1f", insulinNeeded))" +
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
        }
        .onAppear {
            if state.carbRatioItems.isEmpty {
                state.addInitialCarbRatio()
            }
            state.validateCarbRatios()
            therapyItems = state.getCarbRatioTherapyItems()
        }.onChange(of: therapyItems) { _, newItems in
            state.updateCarbRatio(from: newItems)
            refreshUI = UUID()
        }
    }

    // Chart for visualizing carb ratios
    private var carbRatioChart: some View {
        Chart {
            ForEach(Array(state.carbRatioItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = state.carbRatioRateValues[item.rateIndex]

                let startDate = Calendar.current
                    .startOfDay(for: now)
                    .addingTimeInterval(state.carbRatioTimeValues[item.timeIndex])

                var offset: TimeInterval {
                    if state.carbRatioItems.count > index + 1 {
                        return state.carbRatioTimeValues[state.carbRatioItems[index + 1].timeIndex]
                    } else {
                        return state.carbRatioTimeValues.last! + 30 * 60
                    }
                }

                let endDate = Calendar.current.startOfDay(for: now).addingTimeInterval(offset)

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
            domain: Calendar.current.startOfDay(for: now) ... Calendar.current.startOfDay(for: now)
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
