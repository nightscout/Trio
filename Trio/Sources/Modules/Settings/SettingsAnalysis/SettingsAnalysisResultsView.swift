import Charts
import SwiftUI

struct SettingsAnalysisResultsView: View {
    let report: SettingsAnalysis.Report
    let units: GlucoseUnits

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                SettingsAnalysisPrototypeBanner()
            }
            .listRowBackground(Color.chart)

            overviewSection

            SettingsChecksSections(report: report)

            if report.findings.isEmpty {
                Section {
                    Label("No scenarios found in this time frame.", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
                .listRowBackground(Color.chart)
            } else {
                Section {
                    ForEach(report.findings) { finding in
                        NavigationLink(destination: SettingsAnalysisFindingView(finding: finding, units: units)) {
                            FindingRow(finding: finding)
                        }
                    }
                } header: {
                    Text("Detected Scenarios")
                } footer: {
                    Text("Sorted by how often they occur. Tap a scenario to see the advice.")
                }
                .listRowBackground(Color.chart)

                ForEach(report.models) { model in
                    topAdviceSection(for: model)
                }
            }

            if !report.unavailable.isEmpty {
                Section {
                    ForEach(report.unavailable) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            SettingsAnalysisScenarioLabel(scenario: item.scenario, showsSummary: false)
                                .foregroundStyle(.secondary)
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Can't Check")
                }
                .listRowBackground(Color.chart)
            }

            if !report.notDetected.isEmpty {
                Section {
                    ForEach(report.notDetected) { scenario in
                        SettingsAnalysisScenarioLabel(scenario: scenario, showsSummary: false)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Not Detected")
                }
                .listRowBackground(Color.chart)
            }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overviewSection: some View {
        Section {
            LabeledContent("Time Frame", value: report.timeFrame.formatted)
            LabeledContent("Data Model") {
                HStack(spacing: 6) {
                    ForEach(report.models) { model in
                        SettingsAnalysisModelBadge(model: model, size: 22)
                        Text(model.displayName)
                    }
                }
            }
            LabeledContent("Glucose Readings", value: report.readings.formatted())
            LabeledContent("CGM Coverage", value: "\(report.coverage) %")
            LabeledContent {
                Text(report.timeInRange.map { "\($0) %" } ?? "–")
            } label: {
                Text("Time in Range")
                Text(timeInRangeBounds)
            }
            LabeledContent("Logged Meals", value: perDay(report.mealProfile.loggedPerDay))
            LabeledContent("Unannounced Meal Rises", value: perDay(report.mealProfile.unannouncedPerDay))
            if let share = report.mealProfile.prebolusShare {
                LabeledContent("With Manual Prebolus", value: "\(Int((share * 100).rounded())) %")
            }
            LabeledContent(
                "Scenarios Found",
                value: "\(report.findings.count) / \(report.findings.count + report.notDetected.count + report.unavailable.count)"
            )
        } header: {
            Text("Overview")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if report.readings == 0 {
                    Text("No CGM readings found in this time frame, so no scenarios could be detected.")
                } else if report.coverage < 70 {
                    Text("CGM data covers only part of this time frame. Scenarios in the gaps are missed.")
                }
                switch report.mealProfile.style {
                case .announced:
                    EmptyView()
                case .partial:
                    Text("Only some meals are logged, so carb-based scenarios have lower confidence.")
                case .unannounced:
                    Text("Few or no meals are logged, so meals are recognised from fast rises instead of carb entries.")
                }
            }
        }
        .listRowBackground(Color.chart)
    }

    private func perDay(_ value: Double) -> String {
        String(localized: "\(value.formatted(.number.precision(.fractionLength(1)))) / day")
    }

    /// The fixed range the analysis uses, shown in the user's glucose units.
    private var timeInRangeBounds: String {
        let low = SettingsAnalysis.Detectors.Threshold.low.formatted(for: units)
        let high = SettingsAnalysis.Detectors.Threshold.high.formatted(withUnits: units)
        return "\(low)–\(high)"
    }

    private func topAdviceSection(for model: SettingsAnalysis.DataModel) -> some View {
        Section {
            ForEach(report.findings.prefix(3)) { finding in
                if let advice = finding.advice.first(where: { $0.model == model }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(finding.scenario.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(advice.target)
                            .font(.subheadline.weight(.semibold))
                        Text(advice.recommendation)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            HStack(spacing: 6) {
                SettingsAnalysisModelBadge(model: model, size: 18)
                Text("Top Scenario Advice from \(model.displayName)")
            }
        }
        .listRowBackground(Color.chart)
    }
}

private struct FindingRow: View {
    let finding: SettingsAnalysis.Finding

    var body: some View {
        HStack {
            SettingsAnalysisScenarioLabel(scenario: finding.scenario, showsSummary: false)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(finding.count)×")
                    .font(.headline.monospacedDigit())
                SeverityCapsule(severity: finding.severity)
            }
        }
    }
}

struct SeverityCapsule: View {
    let severity: SettingsAnalysis.Severity

    var body: some View {
        Text(severity.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(severity.color)
            .background(severity.color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Finding detail

struct SettingsAnalysisFindingView: View {
    let finding: SettingsAnalysis.Finding
    let units: GlucoseUnits

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    private static let maxListedEvents = 25

    private struct HourBucket: Identifiable {
        let hour: Int
        let count: Int
        var id: Int { hour }
    }

    private var hourBuckets: [HourBucket] {
        let hours = finding.occurrences.map { Calendar.current.component(.hour, from: $0.date) }
        return (0 ..< 24).map { hour in HourBucket(hour: hour, count: hours.filter { $0 == hour }.count) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsAnalysisScenarioLabel(scenario: finding.scenario, showsSummary: false)
                        .font(.headline)
                    Text(finding.scenario.summary)
                        .font(.subheadline)
                    Text(finding.scenario.detectionRule(units: units))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.chart)

            Section {
                LabeledContent("Occurrences", value: "\(finding.count)")
                LabeledContent("Per Week", value: finding.perWeek.formatted(.number.precision(.fractionLength(1))))
                LabeledContent("Frequency") { SeverityCapsule(severity: finding.severity) }
                LabeledContent("Pattern", value: finding.pattern)

                Chart(hourBuckets) { bucket in
                    BarMark(
                        x: .value("Hour", bucket.hour),
                        y: .value("Count", bucket.count)
                    )
                    .foregroundStyle(finding.scenario.color.gradient)
                }
                .chartXScale(domain: 0 ... 23)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hour = value.as(Int.self) { Text(String(format: "%02d:00", hour)) }
                        }
                    }
                }
                .frame(height: 120)
                .padding(.vertical, 6)
                .accessibilityLabel(Text("Occurrences by time of day"))
            } header: {
                Text("In Your Data")
            } footer: {
                Text("Occurrences by time of day.")
            }
            .listRowBackground(Color.chart)

            Section {
                ForEach(finding.advice) { advice in
                    AdviceCard(advice: advice)
                }
                ForEach(finding.guardIDs, id: \.self) { id in
                    Label(guardNote(for: id), systemImage: "shield.lefthalf.filled")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Advice")
            } footer: {
                Text(
                    "Advice describes what a pattern usually points to. Discuss any change with your care team, and change one setting at a time."
                )
            }
            .listRowBackground(Color.chart)

            Section {
                ForEach(finding.occurrences.prefix(Self.maxListedEvents)) { occurrence in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(occurrence.date, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                            .font(.subheadline)
                        Text(occurrence.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Events")
            } footer: {
                if finding.count > Self.maxListedEvents {
                    Text("Showing the \(Self.maxListedEvents) most recent of \(finding.count) events.")
                }
            }
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle(finding.scenario.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guardNote(for id: String) -> String {
        switch id {
        case "P9": return String(localized: "P9: confidence lowered because your DIA is under 8 hours.")
        case "P12": return String(localized: "P12: confidence lowered because only some meals were logged in this time frame.")
        default: return id
        }
    }
}

private struct AdviceCard: View {
    let advice: SettingsAnalysis.Advice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SettingsAnalysisModelBadge(model: advice.model, size: 24)
                Text(advice.model.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ConfidenceBars(confidence: advice.confidence, color: advice.model.color)
            }

            Text(advice.target)
                .font(.caption.weight(.semibold))
                .foregroundStyle(advice.model.color)
                .textCase(.uppercase)

            Text(advice.recommendation)
                .font(.body)

            Text(advice.rationale)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct ConfidenceBars: View {
    let confidence: SettingsAnalysis.Confidence
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < confidence.bars ? color : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(6 + index * 4))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(confidence.displayName))
    }
}
