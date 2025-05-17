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
    @State private var now = Date()

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
        LazyVStack {
            VStack(alignment: .leading, spacing: 0) {
                // Chart visualization
                if !state.isfItems.isEmpty {
                    VStack(alignment: .leading) {
                        isfChart
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
                    unit: state.units == .mgdL ? .mgdLPerUnit : .mmolLPerUnit,
                    timeOptions: state.isfTimeValues,
                    valueOptions: state.isfRateValues,
                    validateOnDelete: state.validateISF
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
                            let firstIsfRate: Decimal = state.isfRateValues[state.isfItems.first?.rateIndex ?? 0]
                            let isfValue = state.units == .mgdL ? firstIsfRate : firstIsfRate.asMmolL
                            let insulinNeeded = aboveTarget / isfValue

                            Text(
                                "If you are \(numberFormatter.string(from: aboveTarget as NSNumber) ?? "--") \(state.units.rawValue) above target:"
                            )
                            .font(.subheadline)
                            .padding(.horizontal)

                            Text(
                                "\(aboveTarget.description) \(state.units.rawValue) / \(isfValue.description) \(state.units.rawValue)/\(String(localized: "U", comment: "Insulin unit abbreviation")) = \(String(format: "%.1f", Double(insulinNeeded))) \(String(localized: "U", comment: "Insulin unit abbreviation"))"
                            )
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.chart.opacity(0.65))
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
                state.addInitialISF()
            }
            state.validateISF()
            therapyItems = state.getISFTherapyItems()
        }.onChange(of: therapyItems) { _, newItems in
            state.updateISF(from: newItems)
            refreshUI = UUID()
        }
    }

    // Chart for visualizing ISF profile
    private var isfChart: some View {
        Chart {
            ForEach(Array(state.isfItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = state.isfRateValues[item.rateIndex]

                let startDate = Calendar.current
                    .startOfDay(for: now)
                    .addingTimeInterval(state.isfTimeValues[item.timeIndex])

                var offset: TimeInterval {
                    if state.isfItems.count > index + 1 {
                        return state.isfTimeValues[state.isfItems[index + 1].timeIndex]
                    } else {
                        return state.isfTimeValues.last! + 30 * 60
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
                            Color.cyan.opacity(0.6),
                            Color.cyan.opacity(0.1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                ).alignsMarkStylesWithPlotArea()

                LineMark(x: .value("End Date", startDate), y: .value("ISF", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.cyan)

                LineMark(x: .value("Start Date", endDate), y: .value("ISF", displayValue))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.cyan)
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
