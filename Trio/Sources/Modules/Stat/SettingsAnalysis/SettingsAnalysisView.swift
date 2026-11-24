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

    /// All presets plus the temp targets and overrides used in the time frame.
    @State private var adjustments: [SettingsAnalysis.AdjustmentUsage] = []
    /// `Adjustment.id`s used for exercise, newline-separated; `nil` until the user picks.
    @AppStorage("SettingsAnalysis.exerciseAdjustments") private var exerciseAdjustmentsRaw: String?

    private var exerciseAdjustments: Set<String>? {
        exerciseAdjustmentsRaw.map { Set($0.split(separator: "\n").map(String.init)) }
    }

    private func isExercise(_ adjustment: SettingsAnalysis.Adjustment) -> Bool {
        exerciseAdjustments?.contains(adjustment.id) ?? adjustment.suggestsExercise
    }

    private struct TimeFrameKey: Hashable {
        let preset: SettingsAnalysis.TimeFramePreset?
        let start: Date
        let end: Date
    }

    /// Stable while a preset is selected, unlike `timeFrame`, which moves with the clock.
    private var timeFrameKey: TimeFrameKey {
        TimeFrameKey(
            preset: preset,
            start: preset == nil ? customStart : .distantPast,
            end: preset == nil ? customEnd : .distantPast
        )
    }

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
        .task(id: timeFrameKey) {
            guard timeFrame.isValid else {
                adjustments = []
                return
            }
            adjustments = await SettingsAnalysis.HistoryLoader.adjustmentUsages(timeFrame)
        }

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

        if !adjustments.isEmpty {
            StatCard {
                SettingsAnalysisLinkRow(destination: SettingsAnalysisExerciseAdjustmentsView(
                    adjustments: adjustments,
                    units: units,
                    isExercise: isExercise,
                    setExercise: setExercise
                )) {
                    Label("Exercise Temp Targets & Overrides", systemImage: "figure.run")
                    Spacer()
                    Text("\(adjustments.filter { isExercise($0.adjustment) }.count) of \(adjustments.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }

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

    private func setExercise(_ adjustment: SettingsAnalysis.Adjustment, _ isOn: Bool) {
        // The first pick starts from what is shown as selected, so nothing else changes.
        var exercise = exerciseAdjustments
            ?? Set(adjustments.map(\.adjustment).filter(\.suggestsExercise).map(\.id))
        if isOn { exercise.insert(adjustment.id) } else { exercise.remove(adjustment.id) }
        exerciseAdjustmentsRaw = exercise.sorted().joined(separator: "\n")
        report = nil
    }

    private func analyze() {
        isAnalyzing = true
        let timeFrame = self.timeFrame
        let exerciseAdjustments = self.exerciseAdjustments
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
                exerciseAdjustments: exerciseAdjustments,
                snapshot: await snapshot(),
                catalog: catalog,
                catalogError: catalogError
            )
            isAnalyzing = false
        }
    }
}

// MARK: - Exercise adjustments

/// Lets the user pick which temp targets and overrides they use for exercise; only those
/// are the basis for Activity Drop.
struct SettingsAnalysisExerciseAdjustmentsView: View {
    let adjustments: [SettingsAnalysis.AdjustmentUsage]
    let units: GlucoseUnits
    let isExercise: (SettingsAnalysis.Adjustment) -> Bool
    let setExercise: (SettingsAnalysis.Adjustment, Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            section(.tempTarget, title: Text("Temp Targets"))
            section(.override, title: Text("Overrides"))
            Section {} footer: {
                Text(
                    "Activity Drop only looks at the temp targets and overrides marked here. Until you change anything, raised temp targets and reduced-insulin overrides are marked. Presets are always listed; custom ones when they were used in the selected time frame."
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func section(_ kind: SettingsAnalysis.Adjustment.Kind, title: Text) -> some View {
        let usages = adjustments.filter { $0.adjustment.kind == kind }
        if !usages.isEmpty {
            Section(header: title) {
                ForEach(usages) { usage in
                    Toggle(isOn: Binding(
                        get: { isExercise(usage.adjustment) },
                        set: { setExercise(usage.adjustment, $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(self.title(usage.adjustment))
                            Text(subtitle(usage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listRowBackground(Color.chart)
        }
    }

    private func title(_ adjustment: SettingsAnalysis.Adjustment) -> String {
        if let name = adjustment.name { return name }
        switch adjustment.kind {
        case .tempTarget: return String(localized: "Custom Temp Target")
        case .override: return String(localized: "Custom Override")
        }
    }

    private func subtitle(_ usage: SettingsAnalysis.AdjustmentUsage) -> String {
        let adjustment = usage.adjustment
        var parts: [String] = []
        if let percentage = adjustment.percentage, Int(percentage.rounded()) != 100 {
            parts.append("\(Int(percentage.rounded()))%")
        }
        if let target = adjustment.target, target > 0 {
            parts.append(target.formatted(withUnits: units))
        }
        if usage.isUnused {
            parts.append(String(localized: "not used in this time frame"))
        } else {
            parts.append(String(localized: "used \(usage.count)×"))
            parts.append(
                Duration.seconds(usage.duration)
                    .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
            )
        }
        return parts.joined(separator: " · ")
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
