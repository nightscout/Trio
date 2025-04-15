//
//  GlucoseTargetStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import Charts
import Foundation
import SwiftUI
import UIKit

/// Glucose target step view for setting target glucose range.
struct GlucoseTargetStepView: View {
    @Bindable var state: Onboarding.StateModel
    @State private var refreshUI = UUID() // to update chart when slider value changes
    @State private var therapyItems: [TherapySettingItem] = []
    @State private var now = Date()

    // Formatter for glucose values
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
                if !state.targetItems.isEmpty {
                    VStack(alignment: .leading) {
                        glucoseTargetChart
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

                // Glucose target list
                TherapySettingEditorView(
                    items: $therapyItems,
                    unit: state.units == .mgdL ? .mgdL : .mmolL,
                    timeOptions: state.targetTimeValues,
                    valueOptions: state.targetRateValues,
                    validateOnDelete: state.validateTarget
                )
            }
        }
        .onAppear {
            if state.targetItems.isEmpty {
                state.addInitialTarget()
            }
            state.validateTarget()
            therapyItems = state.getTargetTherapyItems()
        }.onChange(of: therapyItems) { _, newItems in
            state.updateTargets(from: newItems)
            refreshUI = UUID()
        }
    }

    // Chart for visualizing glucose targets
    private var glucoseTargetChart: some View {
        Chart {
            ForEach(Array(state.targetItems.enumerated()), id: \.element.id) { index, item in
                let rawValue = state.targetRateValues[item.lowIndex]
                let displayValue = state.units == .mgdL ? rawValue : rawValue.asMmolL

                let startDate = Calendar.current
                    .startOfDay(for: now)
                    .addingTimeInterval(state.targetTimeValues[item.timeIndex])

                var offset: TimeInterval {
                    if state.targetItems.count > index + 1 {
                        return state.targetTimeValues[state.targetItems[index + 1].timeIndex]
                    } else {
                        return state.targetTimeValues.last! + 30 * 60
                    }
                }

                let endDate = Calendar.current.startOfDay(for: now).addingTimeInterval(offset)

                LineMark(x: .value("End Date", startDate), y: .value("Ratio", displayValue))
                    .lineStyle(.init(lineWidth: 2.5)).foregroundStyle(Color.green)

                LineMark(x: .value("Start Date", endDate), y: .value("Ratio", displayValue))
                    .lineStyle(.init(lineWidth: 2.5)).foregroundStyle(Color.green)
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
        .chartYScale(
            domain: (state.units == .mgdL ? Decimal(72) : Decimal(72).asMmolL) ...
                (state.units == .mgdL ? Decimal(180) : Decimal(180).asMmolL)
        )
    }
}
