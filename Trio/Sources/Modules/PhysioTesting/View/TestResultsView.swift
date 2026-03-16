import Charts
import SwiftUI

extension PhysioTesting {
    struct TestResultsView: View {
        let metrics: AbsorptionMetrics?
        let testType: TestType
        let readings: [PhysioGlucoseReading]

        @Environment(\.dismiss) var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        if !readings.isEmpty {
                            glucoseChartSection
                        }

                        if let metrics = metrics {
                            metricsSection(metrics)
                        }

                        if !readings.isEmpty {
                            rateOfChangeChartSection
                        }
                    }
                    .padding()
                }
                .navigationTitle("Test Results")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }

        // MARK: - Glucose Chart

        private var glucoseChartSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: testType.iconName)
                        .foregroundColor(.accentColor)
                    Text(testType.displayName)
                        .font(.headline)
                }

                let sortedReadings = readings.sorted { $0.date < $1.date }
                let baseDate = sortedReadings.first?.date ?? Date()

                Chart {
                    // Glucose readings
                    ForEach(Array(sortedReadings.enumerated()), id: \.offset) { _, reading in
                        let minutes = reading.date.timeIntervalSince(baseDate) / 60
                        LineMark(
                            x: .value("Minutes", minutes),
                            y: .value("Glucose", reading.glucose)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Minutes", minutes),
                            y: .value("Glucose", reading.glucose)
                        )
                        .foregroundStyle(.blue)
                        .symbolSize(15)
                    }

                    // Baseline reference
                    if let metrics = metrics, metrics.baselineGlucose > 0 {
                        RuleMark(y: .value("Baseline", metrics.baselineGlucose))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    }
                }
                .frame(height: 200)
                .chartXAxisLabel("Minutes")
                .chartYAxisLabel("mg/dL")
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }

        // MARK: - Metrics Section

        private func metricsSection(_ metrics: AbsorptionMetrics) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Absorption Metrics")
                    .font(.headline)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    metricCard(
                        title: "Onset Delay",
                        value: "\(Int(metrics.onsetDelay)) min",
                        icon: "timer"
                    )
                    metricCard(
                        title: "Peak Absorption Rate",
                        value: String(format: "%.1f mg/dL/min", metrics.peakAbsorptionRate),
                        icon: "arrow.up.right"
                    )
                    metricCard(
                        title: "Time to Peak Rate",
                        value: "\(Int(metrics.timeToPeakRate)) min",
                        icon: "clock.arrow.circlepath"
                    )
                    metricCard(
                        title: "Time to Peak BG",
                        value: "\(Int(metrics.timeToPeakBG)) min",
                        icon: "chart.line.uptrend.xyaxis"
                    )
                    metricCard(
                        title: "Peak Glucose",
                        value: "\(Int(metrics.peakGlucose)) mg/dL",
                        icon: "arrow.up.to.line"
                    )
                    metricCard(
                        title: "Total AUC",
                        value: "\(Int(metrics.totalAUC))",
                        icon: "chart.bar.fill"
                    )
                    metricCard(
                        title: "Absorption Duration",
                        value: "\(Int(metrics.absorptionDuration)) min",
                        icon: "hourglass"
                    )
                    metricCard(
                        title: "Baseline BG",
                        value: "\(Int(metrics.baselineGlucose)) mg/dL",
                        icon: "minus"
                    )
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }

        private func metricCard(title: String, value: String, icon: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(8)
        }

        // MARK: - Rate of Change Chart

        private var rateOfChangeChartSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rate of Change")
                    .font(.headline)

                let sortedReadings = readings.sorted { $0.date < $1.date }
                let baseDate = sortedReadings.first?.date ?? Date()

                // Compute rates
                let rates: [(minutes: Double, rate: Double)] = {
                    var result: [(Double, Double)] = []
                    for i in 1 ..< sortedReadings.count {
                        let dt = sortedReadings[i].date.timeIntervalSince(sortedReadings[i - 1].date) / 60
                        guard dt > 0 else { continue }
                        let dg = Double(sortedReadings[i].glucose) - Double(sortedReadings[i - 1].glucose)
                        let rate = dg / dt
                        let minutes = sortedReadings[i].date.timeIntervalSince(baseDate) / 60
                        result.append((minutes, rate))
                    }
                    return result
                }()

                Chart {
                    ForEach(Array(rates.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Minutes", point.minutes),
                            y: .value("Rate", point.rate)
                        )
                        .foregroundStyle(point.rate >= 0 ? .red : .green)

                        AreaMark(
                            x: .value("Minutes", point.minutes),
                            y: .value("Rate", point.rate)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [point.rate >= 0 ? .red.opacity(0.3) : .green.opacity(0.3), .clear],
                                startPoint: point.rate >= 0 ? .top : .bottom,
                                endPoint: point.rate >= 0 ? .bottom : .top
                            )
                        )
                    }

                    // Zero line
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .frame(height: 150)
                .chartXAxisLabel("Minutes")
                .chartYAxisLabel("mg/dL/min")
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}
