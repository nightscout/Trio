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
    @State private var refreshUI = UUID() // to update chart when slider value changes
    @State private var therapyItems: [TherapySettingItem] = []

    // For chart scaling
    private let chartScale = Calendar.current
        .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = state.units == .mmolL ? 1 : 0
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
                if !state.isfItems.isEmpty {
                    VStack(alignment: .leading) {
                        isfChart
                            .frame(height: 180)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 5)
                    .background(Color.chart.opacity(0.45))
                    .cornerRadius(10)
                }

                TimeValueEditorView(
                    items: $therapyItems,
                    unit: String(localized: "\(state.units.rawValue)/U"),
                    valueOptions: state.isfRateValues
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

                            let isfValue = state.isfRateValues.isEmpty || state.isfItems.isEmpty ?
                                Double(truncating: state.isf as NSNumber) :
                                Double(
                                    truncating: state
                                        .isfRateValues[state.isfItems.first!.rateIndex] as NSNumber
                                )

                            let insulinNeeded = aboveTarget / Decimal(isfValue)

                            Text(
                                "If you are \(numberFormatter.string(from: aboveTarget as NSNumber) ?? "--") \(state.units.rawValue) above target:"
                            )
                            .font(.subheadline)
                            .padding(.horizontal)

                            Text(
                                "\(numberFormatter.string(from: aboveTarget as NSNumber) ?? "--") ÷ \(numberFormatter.string(from: isfValue as NSNumber) ?? "--") = \(String(format: "%.1f", Double(insulinNeeded)))" +
                                    " " + String(localized: "U")
                            )
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.chart.opacity(0.45))
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
                            let isfValue = "\(state.units == .mgdL ? Decimal(50) : 50.asMmolL)" +
                                "\(state.units.rawValue)"
                            Text(
                                "• An ISF of \(isfValue) means 1 U lowers your glucose by \(isfValue)"
                            )
                            Text("• A lower number means you're more sensitive to insulin")
                            Text("• A higher number means you're less sensitive to insulin")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    }
                }
            }
        }
        .onAppear {
            if state.isfItems.isEmpty {
                state.addISFValue()
            }
            therapyItems = state.getSensitivityTherapyItems(from: state.isfItems)
        }.onChange(of: therapyItems) { _, newItems in
            state.updateSensitivies(from: newItems)
            refreshUI = UUID()
        }
    }

    // Add initial ISF value
    private func addInitialISF() {
        // Default to midnight (00:00) and 50 mg/dL (or 2.8 mmol/L)
        let timeIndex = state.isfTimeValues.firstIndex { abs($0 - 0) < 1 } ?? 0
        let defaultISF = state.units == .mgdL ? 50.0 : 2.8
        let rateIndex = state.isfRateValues.firstIndex { abs(Double($0) - defaultISF) < 0.5 } ?? 45

        let newItem = ISFEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
        state.isfItems.append(newItem)
    }

    // Computed property to check if we can add more ISF values
    private var canAddISF: Bool {
        guard let lastItem = state.isfItems.last else { return true }
        return lastItem.timeIndex < state.isfTimeValues.count - 1
    }

    // Chart for visualizing ISF profile
    private var isfChart: some View {
        Chart {
            ForEach(Array(state.isfItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = state.isfRateValues[item.rateIndex]

                let tzOffset = TimeZone.current.secondsFromGMT() * -1
                let startDate = Date(timeIntervalSinceReferenceDate: state.isfTimeValues[item.timeIndex])
                    .addingTimeInterval(TimeInterval(tzOffset))
                let endDate = state.isfItems.count > index + 1 ?
                    Date(
                        timeIntervalSinceReferenceDate: state
                            .isfTimeValues[state.isfItems[index + 1].timeIndex]
                    )
                    .addingTimeInterval(TimeInterval(tzOffset)) :
                    Date(timeIntervalSinceReferenceDate: state.isfTimeValues.last!).addingTimeInterval(30 * 60)
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
