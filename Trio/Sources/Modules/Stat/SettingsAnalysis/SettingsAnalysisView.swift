import SwiftUI

/// The Analysis tab in Statistics: pick a time frame, analyze, see results inline.
struct SettingsAnalysisView: View {
    let units: GlucoseUnits
    /// Reads the current configuration for the settings checks.
    let snapshot: () async -> SettingsAnalysis.SettingsSnapshot

    /// `nil` means a custom time frame.
    @State private var preset: SettingsAnalysis.TimeFramePreset? = .twoWeeks
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()

    @State private var isAnalyzing = false
    @State private var report: SettingsAnalysis.Report?

    private var timeFrame: SettingsAnalysis.TimeFrame {
        if let preset { return .preset(preset) }
        return SettingsAnalysis.TimeFrame(start: customStart, end: customEnd)
    }

    private var canAnalyze: Bool {
        !isAnalyzing && timeFrame.isValid
    }

    var body: some View {
        Picker("Time Frame", selection: $preset) {
            ForEach(SettingsAnalysis.TimeFramePreset.allCases) { preset in
                Text(preset.displayName).tag(Optional(preset))
            }
            Text("Custom").tag(SettingsAnalysis.TimeFramePreset?.none)
        }
        .pickerStyle(.segmented)
        .onChange(of: preset) { report = nil }
        .onChange(of: customStart) { report = nil }
        .onChange(of: customEnd) { report = nil }

        if preset == nil {
            StatCard {
                VStack(spacing: 8) {
                    DatePicker(
                        "From",
                        selection: $customStart,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Divider()
                    DatePicker(
                        "To",
                        selection: $customEnd,
                        in: customStart ... Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
        }

        Group {
            if !timeFrame.isValid {
                Text("The end of the time frame must be after its start.")
            } else if preset != nil {
                Text("Looks for recurring patterns over a longer period. \(timeFrame.formatted)")
            } else {
                Text("Pick a specific window, for example a single meal or night, to analyze individual events.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)

        Button(action: analyze) {
            HStack {
                if isAnalyzing {
                    ProgressView()
                        .padding(.trailing, 6)
                    Text("Analyzing…")
                } else {
                    Label("Analyze", systemImage: "sparkle.magnifyingglass")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canAnalyze)

        NavigationLink(destination: SettingsAnalysisScenariosInfoView(units: units)) {
            HStack {
                Label("About the Scenarios", systemImage: "info.circle")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)

        if let report {
            SettingsAnalysisResultsView(report: report, units: units)
        }

        StatCard {
            SettingsAnalysisPrototypeBanner()
        }
    }

    // MARK: Actions

    private func analyze() {
        isAnalyzing = true
        let timeFrame = self.timeFrame
        Task { @MainActor in
            var catalog: SettingsAnalysis.Catalog?
            var catalogError: String?
            do {
                catalog = try SettingsAnalysis.Catalog.loadBundled()
            } catch {
                catalogError = error.localizedDescription
            }
            report = await SettingsAnalysis.Engine(units: units).analyze(
                timeFrame: timeFrame,
                snapshot: await snapshot(),
                catalog: catalog,
                catalogError: catalogError
            )
            isAnalyzing = false
        }
    }
}

// MARK: - Shared components

/// A titled card in the Statistics style, with an optional footer below it.
struct SettingsAnalysisCard<Content: View, Footer: View>: View {
    let title: Text?
    let content: Content
    let footer: Footer

    init(
        _ title: Text? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatCard {
                VStack(alignment: .leading, spacing: 10) {
                    if let title {
                        title.font(.headline)
                    }
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }
}

/// A tappable card row that pushes `destination`.
struct SettingsAnalysisLinkRow<Label: View, Destination: View>: View {
    let destination: Destination
    let label: Label

    init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                label
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsAnalysisPrototypeBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Prototype")
                    .font(.headline)
                Text(
                    "Settings checks use your current settings, and scenarios are detected in your stored glucose, carb and insulin data. The advice is general wording per scenario, not medical advice; always talk to your care team before changing settings."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsAnalysisScenarioLabel: View {
    let scenario: SettingsAnalysis.Scenario
    var showsSummary = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: scenario.icon)
                .foregroundStyle(scenario.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.title)
                if showsSummary {
                    Text(scenario.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
