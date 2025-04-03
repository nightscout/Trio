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
    @Bindable var state: Onboarding.StateModel
    @State private var refreshUI = UUID() // to update chart when slider value changes
    @State private var therapyItems: [TherapySettingItem] = []

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

    // For chart scaling
    private let chartScale = Calendar.current
        .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))

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
                TimeValueEditorView(
                    items: $therapyItems,
                    unit: state.units.rawValue,
                    timeOptions: state.targetTimeValues,
                    valueOptions: state.targetRateValues
                )
            }
        }
        .onAppear {
            if state.targetItems.isEmpty {
                addTarget()
            }
            state.validateTarget()
            therapyItems = state.getTargetTherapyItems(from: state.targetItems)
        }.onChange(of: therapyItems) { _, newItems in
            state.updateTargets(from: newItems)
            refreshUI = UUID()
        }
    }

    // Add initial target
    private func addTarget() {
        // Default to midnight (00:00) and 1.0 U/h rate
        let timeIndex = state.targetTimeValues.firstIndex { abs($0 - 0) < 1 } ?? 0
        let targetIndex = state.targetRateValues.firstIndex { abs(Double($0) - 100) < 0.05 } ?? 100

        let newItem = TargetsEditor.Item(lowIndex: targetIndex, highIndex: targetIndex, timeIndex: timeIndex)
        state.targetItems.append(newItem)
    }

    // Computed property to check if we can add more targets
    private var canAddTarget: Bool {
        guard let lastItem = state.targetItems.last else { return true }
        return lastItem.timeIndex < state.targetTimeValues.count - 1
    }

    // Chart for visualizing glucose targets
    private var glucoseTargetChart: some View {
        Chart {
            ForEach(Array(state.targetItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = state.targetRateValues[item.lowIndex]

                let tzOffset = TimeZone.current.secondsFromGMT() * -1
                let startDate = Date(timeIntervalSinceReferenceDate: state.targetTimeValues[item.timeIndex])
                    .addingTimeInterval(TimeInterval(tzOffset))
                let endDate = state.targetItems.count > index + 1 ?
                    Date(
                        timeIntervalSinceReferenceDate: state
                            .targetTimeValues[state.targetItems[index + 1].timeIndex]
                    )
                    .addingTimeInterval(TimeInterval(tzOffset)) :
                    Date(timeIntervalSinceReferenceDate: state.targetTimeValues.last!).addingTimeInterval(30 * 60)
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
