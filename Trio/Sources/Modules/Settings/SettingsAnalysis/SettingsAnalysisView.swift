import SwiftUI

/// Entry point for Settings → Support & Community → Settings Analysis.
struct SettingsAnalysisView: View {
    let units: GlucoseUnits
    /// Reads the current configuration for the settings checks.
    let snapshot: () async -> SettingsAnalysis.SettingsSnapshot

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var timeFrameMode: SettingsAnalysis.TimeFrameMode = .preset
    @State private var preset: SettingsAnalysis.TimeFramePreset = .month
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var selectedScenarios = Set(SettingsAnalysis.Scenario.allCases)

    @State private var isAnalyzing = false
    @State private var report: SettingsAnalysis.Report?

    private var timeFrame: SettingsAnalysis.TimeFrame {
        switch timeFrameMode {
        case .preset: return .preset(preset)
        case .custom: return SettingsAnalysis.TimeFrame(start: customStart, end: customEnd)
        }
    }

    private var canAnalyze: Bool {
        !isAnalyzing && !selectedScenarios.isEmpty && timeFrame.isValid
    }

    var body: some View {
        List {
            Section {
                SettingsAnalysisPrototypeBanner()
            }
            .listRowBackground(Color.chart)

            modelSection
            timeFrameSection
            scenarioSection

            Section {
                Button(action: analyze) {
                    HStack {
                        Spacer()
                        if isAnalyzing {
                            ProgressView()
                                .padding(.trailing, 6)
                            Text("Analyzing…")
                        } else {
                            Label("Analyze", systemImage: "sparkle.magnifyingglass")
                        }
                        Spacer()
                    }
                    .font(.headline)
                }
                .disabled(!canAnalyze)
            } footer: {
                if selectedScenarios.isEmpty {
                    Text("Select at least one scenario.")
                } else if !timeFrame.isValid {
                    Text("The end of the time frame must be after its start.")
                }
            }
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Settings Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(
            isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })
        ) {
            if let report {
                SettingsAnalysisResultsView(report: report, units: units)
            }
        }
    }

    // MARK: Sections

    private var modelSection: some View {
        Section {
            ForEach(SettingsAnalysis.DataModel.allCases) { model in
                SettingsAnalysisModelRow(model: model)
            }

            NavigationLink(destination: SettingsAnalysisModelsInfoView()) {
                Text("About the Data Model")
            }

            NavigationLink(destination: SettingsAnalysisGuardsInfoView()) {
                Text("How Advice Is Checked")
            }
        } header: {
            Text("Data Model")
        }
        .listRowBackground(Color.chart)
    }

    private var timeFrameSection: some View {
        Section {
            Picker("Time Frame", selection: $timeFrameMode) {
                ForEach(SettingsAnalysis.TimeFrameMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch timeFrameMode {
            case .preset:
                Picker("Last", selection: $preset) {
                    ForEach(SettingsAnalysis.TimeFramePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
            case .custom:
                DatePicker(
                    "From",
                    selection: $customStart,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                DatePicker(
                    "To",
                    selection: $customEnd,
                    in: customStart ... Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        } header: {
            Text("Time Frame")
        } footer: {
            switch timeFrameMode {
            case .preset:
                Text("Looks for recurring patterns over a longer period. \(timeFrame.formatted)")
            case .custom:
                Text("Pick a specific window, for example a single meal or night, to analyze individual events.")
            }
        }
        .listRowBackground(Color.chart)
    }

    private var scenarioSection: some View {
        Section {
            ForEach(SettingsAnalysis.Scenario.allCases) { scenario in
                Toggle(isOn: binding(for: scenario)) {
                    SettingsAnalysisScenarioLabel(scenario: scenario)
                }
            }

            NavigationLink(destination: SettingsAnalysisScenariosInfoView(units: units)) {
                Text("About the Scenarios")
            }
        } header: {
            HStack {
                Text("Scenarios")
                Spacer()
                let allSelected = selectedScenarios.count == SettingsAnalysis.Scenario.allCases.count
                Button {
                    selectedScenarios = allSelected ? [] : Set(SettingsAnalysis.Scenario.allCases)
                } label: {
                    if allSelected { Text("Select None") } else { Text("Select All") }
                }
                .font(.caption)
                .textCase(nil)
            }
        }
        .listRowBackground(Color.chart)
    }

    // MARK: Actions

    private func binding(for scenario: SettingsAnalysis.Scenario) -> Binding<Bool> {
        Binding(
            get: { selectedScenarios.contains(scenario) },
            set: { isOn in
                if isOn { selectedScenarios.insert(scenario) } else { selectedScenarios.remove(scenario) }
            }
        )
    }

    private func analyze() {
        isAnalyzing = true
        let timeFrame = self.timeFrame
        let scenarios = selectedScenarios
        let models = SettingsAnalysis.DataModel.allCases
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
                scenarios: scenarios,
                models: models,
                snapshot: await snapshot(),
                catalog: catalog,
                catalogError: catalogError
            )
            isAnalyzing = false
        }
    }
}

// MARK: - Shared components

struct SettingsAnalysisPrototypeBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flask")
                .font(.title2)
                .foregroundStyle(.orange)
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
        .padding(.vertical, 4)
    }
}

struct SettingsAnalysisModelRow: View {
    let model: SettingsAnalysis.DataModel

    var body: some View {
        HStack(spacing: 12) {
            SettingsAnalysisModelBadge(model: model, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.headline)
                Text(model.tagline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SettingsAnalysisModelBadge: View {
    let model: SettingsAnalysis.DataModel
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: model.icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(model.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
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
