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
    @State private var now = Date()
    @Namespace private var bottomID

    private var rateFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack {
                VStack(alignment: .leading, spacing: 0) {
                    // Chart visualization
                    if !state.basalProfileItems.isEmpty {
                        VStack(alignment: .leading) {
                            basalProfileChart
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
                        unit: .unitPerHour,
                        timeOptions: state.basalProfileTimeValues,
                        valueOptions: state.basalProfileRateValues,
                        validateOnDelete: state.validateBasal,
                        onItemAdded: {
                            withAnimation {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        }
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
                                    Text(rateFormatter.string(from: state.totalDailyBasal() as NSNumber) ?? "0")
                                    Text("U/day")
                                        .foregroundStyle(Color.secondary)
                                }
                                .id(refreshUI) // Erzwingt die Aktualisierung des Totals
                            }
                        }
                        .padding()
                        .background(Color.chart.opacity(0.65))
                        .cornerRadius(10)
                        .id(bottomID)
                    }
                }
            }
            .onAppear {
                if state.basalProfileItems.isEmpty {
                    state.addInitialBasalRate()
                }
                state.validateBasal()
                therapyItems = state.getBasalTherapyItems()
            }.onChange(of: therapyItems) { _, newItems in
                state.updateBasal(from: newItems)
                refreshUI = UUID()
            }
        }
    }

    // Chart for visualizing basal profile
    private var basalProfileChart: some View {
        Chart {
            ForEach(Array(state.basalProfileItems.enumerated()), id: \.element.id) { index, item in
                let displayValue = state.basalProfileRateValues[item.rateIndex]

                let startDate = Calendar.current
                    .startOfDay(for: now)
                    .addingTimeInterval(state.basalProfileTimeValues[item.timeIndex])

                var offset: TimeInterval {
                    if state.basalProfileItems.count > index + 1 {
                        return state.basalProfileTimeValues[state.basalProfileItems[index + 1].timeIndex]
                    } else {
                        return state.basalProfileTimeValues.last! + 30 * 60
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
