import Charts
import SwiftUI

extension PhysioTesting {
    struct TestResultsView: View {
        let metrics: AbsorptionMetrics?
        let testType: TestType
        let readings: [PhysioGlucoseReading]
        var presentedAsSheet: Bool = false
        var onApplyProfile: ((AbsorptionMetrics) -> Void)?
        var onRevertToDefaults: (() -> Void)?
        var isCustomProfileActive: Bool = false

        @Environment(\.dismiss) var dismiss
        @State private var showApplyConfirm = false
        @State private var showRevertConfirm = false
        @State private var showStandardCurve = true

        var body: some View {
            if presentedAsSheet {
                NavigationStack {
                    resultsContent
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            } else {
                resultsContent
            }
        }

        private var resultsContent: some View {
            ScrollView {
                VStack(spacing: 20) {
                    if !readings.isEmpty {
                        glucoseChartSection
                    }

                    if let metrics = metrics {
                        metricsSection(metrics)
                        profileActionSection(metrics)
                    }

                    if !readings.isEmpty {
                        rateOfChangeChartSection
                    }
                }
                .padding()
            }
            .navigationTitle("Test Results")
            .navigationBarTitleDisplayMode(.inline)
        }

        // MARK: - Glucose Chart with Standard Curve

        private var glucoseChartSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: testType.iconName)
                        .foregroundColor(.accentColor)
                    Text(testType.displayName)
                        .font(.headline)
                    Spacer()
                    Toggle("Standard", isOn: $showStandardCurve)
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .font(.caption)
                }

                let sortedReadings = readings.sorted { $0.date < $1.date }
                let mealStartMinutes = mealStartOffset(sortedReadings: sortedReadings)

                Chart {
                    // Actual glucose readings (relative to meal start)
                    ForEach(Array(sortedReadings.enumerated()), id: \.offset) { _, reading in
                        let minutes = minutesSinceMealStart(reading: reading, sortedReadings: sortedReadings)
                        LineMark(
                            x: .value("Minutes", minutes),
                            y: .value("Glucose", reading.glucose),
                            series: .value("Series", "Actual")
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

                    // Standard curve overlay
                    if showStandardCurve, let metrics = metrics {
                        let standardPoints = StandardAbsorptionCurve.generate(
                            baseline: metrics.baselineGlucose,
                            peakGlucose: metrics.peakGlucose,
                            testType: testType
                        )
                        ForEach(Array(standardPoints.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Minutes", point.minutes),
                                y: .value("Glucose", point.glucose),
                                series: .value("Series", "Standard")
                            )
                            .foregroundStyle(.orange.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        }
                    }

                    // Baseline reference
                    if let metrics = metrics, metrics.baselineGlucose > 0 {
                        RuleMark(y: .value("Baseline", metrics.baselineGlucose))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    }
                }
                .frame(height: 220)
                .chartXAxisLabel("Minutes from Meal")
                .chartYAxisLabel("mg/dL")
                .chartForegroundStyleScale([
                    "Actual": Color.blue,
                    "Standard": Color.orange.opacity(0.7)
                ])
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

                let standard = StandardAbsorptionCurve.standardMetrics(for: testType)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    metricComparisonCard(
                        title: "Onset Delay",
                        value: "\(Int(metrics.onsetDelay)) min",
                        standard: "\(Int(standard.onsetDelay)) min",
                        icon: "timer"
                    )
                    metricComparisonCard(
                        title: "Peak Rate",
                        value: String(format: "%.1f mg/dL/min", metrics.peakAbsorptionRate),
                        standard: nil,
                        icon: "arrow.up.right"
                    )
                    metricComparisonCard(
                        title: "Time to Peak Rate",
                        value: "\(Int(metrics.timeToPeakRate)) min",
                        standard: "\(Int(standard.timeToPeakRate)) min",
                        icon: "clock.arrow.circlepath"
                    )
                    metricComparisonCard(
                        title: "Time to Peak BG",
                        value: "\(Int(metrics.timeToPeakBG)) min",
                        standard: "\(Int(standard.timeToPeakBG)) min",
                        icon: "chart.line.uptrend.xyaxis"
                    )
                    metricComparisonCard(
                        title: "Peak Glucose",
                        value: "\(Int(metrics.peakGlucose)) mg/dL",
                        standard: nil,
                        icon: "arrow.up.to.line"
                    )
                    metricComparisonCard(
                        title: "Total AUC",
                        value: "\(Int(metrics.totalAUC))",
                        standard: nil,
                        icon: "chart.bar.fill"
                    )
                    metricComparisonCard(
                        title: "Absorption Duration",
                        value: "\(Int(metrics.absorptionDuration)) min",
                        standard: "\(Int(standard.absorptionDuration)) min",
                        icon: "hourglass"
                    )
                    metricComparisonCard(
                        title: "Baseline BG",
                        value: "\(Int(metrics.baselineGlucose)) mg/dL",
                        standard: nil,
                        icon: "minus"
                    )
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }

        private func metricComparisonCard(title: String, value: String, standard: String?, icon: String) -> some View {
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
                if let standard = standard {
                    Text("Std: \(standard)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(8)
        }

        // MARK: - Profile Action Section

        private func profileActionSection(_ metrics: AbsorptionMetrics) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Absorption Profile")
                    .font(.headline)

                if isCustomProfileActive {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Custom profile from this test is active")
                            .font(.subheadline)
                    }
                }

                if onApplyProfile != nil {
                    Button {
                        showApplyConfirm = true
                    } label: {
                        Label(
                            isCustomProfileActive ? "Re-apply Custom Profile" : "Apply Custom Profile",
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .confirmationDialog(
                        "Apply Custom Absorption Profile?",
                        isPresented: $showApplyConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Apply Profile") {
                            onApplyProfile?(metrics)
                        }
                    } message: {
                        Text(
                            "This will update your absorption model with parameters from this test. " +
                            "The adaptive learning system will use your personal curve instead of population defaults."
                        )
                    }
                }

                if onRevertToDefaults != nil {
                    Button {
                        showRevertConfirm = true
                    } label: {
                        Label("Revert to Default Profile", systemImage: "arrow.uturn.backward.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .confirmationDialog(
                        "Revert to Default Absorption Profile?",
                        isPresented: $showRevertConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Revert to Defaults", role: .destructive) {
                            onRevertToDefaults?()
                        }
                    } message: {
                        Text(
                            "This will reset your absorption model back to population defaults. " +
                            "All learned personalization will be cleared."
                        )
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }

        // MARK: - Rate of Change Chart

        private var rateOfChangeChartSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rate of Change")
                    .font(.headline)

                let sortedReadings = readings.sorted { $0.date < $1.date }

                // Compute rates relative to meal start
                let rates: [(minutes: Double, rate: Double)] = {
                    var result: [(Double, Double)] = []
                    for i in 1 ..< sortedReadings.count {
                        let dt = sortedReadings[i].date.timeIntervalSince(sortedReadings[i - 1].date) / 60
                        guard dt > 0 else { continue }
                        let dg = Double(sortedReadings[i].glucose) - Double(sortedReadings[i - 1].glucose)
                        let rate = dg / dt
                        let minutes = minutesSinceMealStart(reading: sortedReadings[i], sortedReadings: sortedReadings)
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
                .chartXAxisLabel("Minutes from Meal")
                .chartYAxisLabel("mg/dL/min")
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }

        // MARK: - Helpers

        private func mealStartOffset(sortedReadings: [PhysioGlucoseReading]) -> Double {
            guard let metrics = metrics, let first = sortedReadings.first else { return 0 }
            // Meal happened onsetDelay minutes before the first detectable rise
            // We use the onset delay from metrics; readings start from test start (baseline period)
            return 0
        }

        private func minutesSinceMealStart(reading: PhysioGlucoseReading, sortedReadings: [PhysioGlucoseReading]) -> Double {
            guard let first = sortedReadings.first else { return 0 }
            return reading.date.timeIntervalSince(first.date) / 60
        }
    }
}

// MARK: - Standard Absorption Curve

/// Generates a standard/population-average glucose response curve for comparison
enum StandardAbsorptionCurve {
    struct CurvePoint {
        let minutes: Double
        let glucose: Double
    }

    struct StandardMetrics {
        let onsetDelay: Double
        let timeToPeakRate: Double
        let timeToPeakBG: Double
        let absorptionDuration: Double
    }

    /// Standard timing metrics by test type (population averages from literature)
    static func standardMetrics(for testType: PhysioTesting.TestType) -> StandardMetrics {
        switch testType {
        case .pureCarbs:
            return StandardMetrics(
                onsetDelay: 15,
                timeToPeakRate: 45,
                timeToPeakBG: 75,
                absorptionDuration: 180
            )
        case .carbsFat:
            return StandardMetrics(
                onsetDelay: 25,
                timeToPeakRate: 70,
                timeToPeakBG: 105,
                absorptionDuration: 270
            )
        case .carbsProtein:
            return StandardMetrics(
                onsetDelay: 20,
                timeToPeakRate: 55,
                timeToPeakBG: 90,
                absorptionDuration: 240
            )
        case .mixed:
            return StandardMetrics(
                onsetDelay: 30,
                timeToPeakRate: 75,
                timeToPeakBG: 120,
                absorptionDuration: 300
            )
        }
    }

    /// Generate standard curve points scaled to match the test's baseline and peak glucose
    static func generate(
        baseline: Double,
        peakGlucose: Double,
        testType: PhysioTesting.TestType
    ) -> [CurvePoint] {
        let std = standardMetrics(for: testType)
        let rise = peakGlucose - baseline
        guard rise > 0 else { return [] }

        // Generate normalized curve shape (0 to 1 scale)
        // Uses a skewed bell curve: fast rise to peak, slower return
        var points: [CurvePoint] = []
        let totalMinutes = std.absorptionDuration + std.onsetDelay
        let step: Double = 5

        var t: Double = 0
        while t <= totalMinutes {
            let fraction: Double
            if t < std.onsetDelay {
                // Before onset: flat at baseline
                fraction = 0
            } else {
                let elapsed = t - std.onsetDelay
                let peakTime = std.timeToPeakBG - std.onsetDelay

                if elapsed <= peakTime {
                    // Rising phase: smooth S-curve to peak
                    let x = elapsed / peakTime
                    // Smoothstep gives a natural S-curve rise
                    fraction = x * x * (3 - 2 * x)
                } else {
                    // Falling phase: exponential decay back to baseline
                    let decayTime = std.absorptionDuration - peakTime
                    let elapsed2 = elapsed - peakTime
                    guard decayTime > 0 else {
                        fraction = 0
                        points.append(CurvePoint(minutes: t, glucose: baseline + rise * fraction))
                        t += step
                        continue
                    }
                    fraction = exp(-2.5 * elapsed2 / decayTime)
                }
            }

            points.append(CurvePoint(minutes: t, glucose: baseline + rise * fraction))
            t += step
        }

        return points
    }
}
