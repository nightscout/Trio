import SwiftUI
import Swinject

// MARK: - Module Namespace

enum SmartSenseConfig {
    enum Config {}
}

protocol SmartSenseConfigProvider {}

extension SmartSenseConfig {
    final class Provider: BaseProvider, SmartSenseConfigProvider {}
}

// MARK: - State Model

extension SmartSenseConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var signalPipeline: OrefSignalPipeline!

        @Published var smartSenseEnabled: Bool = false
        @Published var garminEnabled: Bool = false
        @Published var garminSplit: Double = 0.60
        @Published var maxAdjustment: Double = 0.20
        @Published var overrideDuration: Double = 6.0
        @Published var weights: SmartSenseWeights = SmartSenseWeights()

        // Oref Enhancement Toggles (Phases 2–5)
        @Published var macroMealModelEnabled: Bool = false
        @Published var dailyStateVectorEnabled: Bool = false
        @Published var exerciseSensitivityEnabled: Bool = false
        @Published var adaptiveLearningEnabled: Bool = false

        override func subscribe() {
            let settings = settingsManager.settings.smartSenseSettings
            smartSenseEnabled = settings.enabled
            garminEnabled = settings.garminEnabled
            garminSplit = settings.garminSplit
            maxAdjustment = settings.maxAdjustment
            overrideDuration = settings.overrideDurationHours
            weights = settings.weights
            macroMealModelEnabled = settings.macroMealModelEnabled
            dailyStateVectorEnabled = settings.dailyStateVectorEnabled
            exerciseSensitivityEnabled = settings.exerciseSensitivityEnabled
            adaptiveLearningEnabled = settings.adaptiveLearningEnabled

            $macroMealModelEnabled
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] value in
                    self?.settingsManager.settings.smartSenseSettings.macroMealModelEnabled = value
                }
                .store(in: &lifetime)

            $dailyStateVectorEnabled
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] value in
                    self?.settingsManager.settings.smartSenseSettings.dailyStateVectorEnabled = value
                }
                .store(in: &lifetime)

            $exerciseSensitivityEnabled
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] value in
                    self?.settingsManager.settings.smartSenseSettings.exerciseSensitivityEnabled = value
                }
                .store(in: &lifetime)

            $adaptiveLearningEnabled
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] value in
                    self?.settingsManager.settings.smartSenseSettings.adaptiveLearningEnabled = value
                }
                .store(in: &lifetime)

            $smartSenseEnabled
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] value in
                    self?.settingsManager.settings.smartSenseSettings.enabled = value
                }
                .store(in: &lifetime)

            $garminEnabled
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] value in
                    self?.settingsManager.settings.smartSenseSettings.garminEnabled = value
                    if value {
                        Task { await GarminFirebaseManager.configureAndSignIn() }
                    }
                }
                .store(in: &lifetime)

            $garminSplit
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] value in
                    self?.settingsManager.settings.smartSenseSettings.garminSplit = value
                }
                .store(in: &lifetime)

            $overrideDuration
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] value in
                    self?.settingsManager.settings.smartSenseSettings.overrideDurationHours = value
                }
                .store(in: &lifetime)
        }

        func updateWeight(key: SmartSenseWeights.FactorKey, value: Double) {
            weights[key] = value
            settingsManager.settings.smartSenseSettings.weights = weights
        }

        var currentSmartSenseSettings: SmartSenseSettings {
            settingsManager.settings.smartSenseSettings
        }
    }
}

// MARK: - Root View

extension SmartSenseConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = SmartSenseConfig.StateModel()

        @State private var exportFiles: [URL] = []
        @State private var showShareSheet = false
        @State private var snapshotCount = 0
        @State private var selectedRange: MealDecisionExporter.ExportRange = .sevenDays
        @State private var selectedFilter: MealDecisionExporter.ExportFilter = .all
        @State private var isExporting = false

        var body: some View {
            Form {
                enableSection
                if state.smartSenseEnabled {
                    garminSection
                    masterSplitSection
                    weightEditorSection
                    overrideSection
                    orefEnhancementsSection
                    exportSection
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Smart Sense")
            .navigationBarTitleDisplayMode(.automatic)
            .onAppear {
                configureView()
                snapshotCount = MealDecisionExporter.snapshotCount(for: selectedRange, filter: selectedFilter)
            }
            .sheet(isPresented: $showShareSheet) {
                if !exportFiles.isEmpty {
                    ShareSheet(activityItems: exportFiles)
                }
            }
        }

        // MARK: - Sections

        private var enableSection: some View {
            Section(header: Text("Smart Sense")) {
                Toggle("Enable Smart Sense", isOn: $state.smartSenseEnabled)
                if state.smartSenseEnabled {
                    Text("Adjusts insulin sensitivity using Garmin health data and autosens. Modifies ISF/CR so the entire oref loop respects the adjustment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private var garminSection: some View {
            Section(header: Text("Garmin Data Source")) {
                Toggle("Enable Garmin Integration", isOn: $state.garminEnabled)
                if state.garminEnabled {
                    NavigationLink(value: Screen.garminFirestoreStatus) {
                        HStack {
                            Text("Garmin Health Data")
                            Spacer()
                            Text(GarminFirebaseConstants.isConfigured ? "Configured" : "Not Configured")
                                .font(.caption)
                                .foregroundStyle(GarminFirebaseConstants.isConfigured ? .green : .red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        infoRow(icon: "moon.zzz.fill", color: .indigo,
                                title: "Sleep Quality",
                                desc: "Poor sleep reduces insulin sensitivity")
                        infoRow(icon: "figure.run", color: .green,
                                title: "Activity Level",
                                desc: "Recent exercise improves sensitivity")
                        infoRow(icon: "heart.fill", color: .red,
                                title: "Resting Heart Rate",
                                desc: "Elevated RHR suggests stress or illness")
                        infoRow(icon: "waveform.path.ecg", color: .orange,
                                title: "HRV",
                                desc: "Low HRV indicates reduced recovery")
                    }
                    .padding(.vertical, 4)
                }
            }
        }

        private var masterSplitSection: some View {
            Section(header: Text("Source Blending")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Garmin")
                        Spacer()
                        Text("\(Int(state.garminSplit * 100))%")
                            .monospacedDigit()
                    }
                    Slider(value: $state.garminSplit, in: 0 ... 1, step: 0.05)
                    HStack {
                        Text("Autosens")
                        Spacer()
                        Text("\(Int((1.0 - state.garminSplit) * 100))%")
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }

                Text("If Garmin data is unavailable, autosens automatically gets 100%. The sensitivity slider on the treatment screen still allows manual adjustment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Max Adjustment")
                    Spacer()
                    Text("+-\(Int(state.maxAdjustment * 100))%")
                        .monospacedDigit()
                }
            }
        }

        private var weightEditorSection: some View {
            Section(header: weightEditorHeader) {
                ForEach(SmartSenseWeights.allFactors) { key in
                    HStack {
                        Image(systemName: key.icon)
                            .foregroundStyle(iconColor(for: key))
                            .frame(width: 24)
                        Text(key.displayName)
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(state.weights[key] * 100))%")
                            .monospacedDigit()
                            .font(.subheadline)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Slider(value: Binding(
                        get: { state.weights[key] },
                        set: { state.updateWeight(key: key, value: $0) }
                    ), in: 0 ... 0.5, step: 0.025)
                }
            }
        }

        private var weightEditorHeader: some View {
            HStack {
                Text("Garmin Factor Weights")
                Spacer()
                let total = Int(state.weights.total * 100)
                Text("Total: \(total)%")
                    .foregroundStyle(total == 100 ? .green : .red)
                    .font(.caption.weight(.semibold))
            }
        }

        private var overrideSection: some View {
            Section(header: Text("Per-Dose Override")) {
                HStack {
                    Text("Override Duration")
                    Spacer()
                    Text("\(Int(state.overrideDuration))h")
                        .monospacedDigit()
                }
                Slider(value: $state.overrideDuration, in: 2 ... 10, step: 1)
                Text("When you adjust the sensitivity slider at dose time, the override persists for this duration so the loop respects your adjustment through meal absorption.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        private var orefEnhancementsSection: some View {
            Section(header: Text("Oref Enhancements"), footer: Text("These features compute and log data in shadow mode at all times. Enabling a toggle allows the computed values to modify oref's dosing decisions. Export signal data to review shadow-mode output before enabling.")) {
                Toggle(isOn: $state.macroMealModelEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Macro-Aware Meal Model")
                        Text("Bayesian COB from carb/fat/protein/fiber. Replaces linear absorption.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $state.dailyStateVectorEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily State Vector")
                        Text("ISF/CR modifiers from HRV, sleep quality, body battery, resting HR.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $state.exerciseSensitivityEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exercise Sensitivity")
                        Text("Post-exercise ISF/CR curves and glycogen depletion modeling.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $state.adaptiveLearningEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adaptive Learning")
                        Text("EWMA personalization of absorption speed, protein/fat sensitivity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private var exportSection: some View {
            Group {
                Section(header: Text("Meal Decision Export")) {
                    Picker("Export Range", selection: $selectedRange) {
                        ForEach(MealDecisionExporter.ExportRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .onChange(of: selectedRange) { newRange in
                        snapshotCount = MealDecisionExporter.snapshotCount(for: newRange, filter: selectedFilter)
                    }
                }

                Section(header: Text("Meal Source Filter")) {
                    Picker("Meal Source", selection: $selectedFilter) {
                        ForEach(MealDecisionExporter.ExportFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedFilter) { newFilter in
                        snapshotCount = MealDecisionExporter.snapshotCount(for: selectedRange, filter: newFilter)
                    }

                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.blue)
                        Text("Meal Decisions")
                        Spacer()
                        Text("\(snapshotCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Button {
                        guard !isExporting else { return }
                        isExporting = true
                        Task {
                            let context = CoreDataStack.shared.newTaskContext()
                            let settings = state.currentSmartSenseSettings
                            if let url = await MealDecisionExporter.buildFullExport(
                                range: selectedRange,
                                filter: selectedFilter,
                                settings: settings,
                                context: context,
                                signalStore: state.signalPipeline.store
                            ) {
                                exportFiles = [url]
                                showShareSheet = true
                            }
                            isExporting = false
                        }
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text("Export Meal Data")
                        }
                    }
                    .disabled(snapshotCount == 0 || isExporting)

                    Text("Exports meal decisions with 2h pre-meal + 8h post-meal BG traces, all boluses, temp basals, loop decisions, and settings as JSON. Filter by Smart Sense (detected) or Manual entries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("Signal Pipeline Export")) {
                    Button {
                        guard !isExporting else { return }
                        isExporting = true
                        Task {
                            if let url = MealDecisionExporter.buildSignalExport(
                                range: selectedRange,
                                signalStore: state.signalPipeline.store
                            ) {
                                exportFiles = [url]
                                showShareSheet = true
                            }
                            isExporting = false
                        }
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "waveform.path.ecg")
                            }
                            Text("Export Signal Data")
                        }
                    }
                    .disabled(isExporting)

                    Text("Exports the continuous signal pipeline log: Kalman-filtered BG, velocity, acceleration, jerk, residuals, meal detection confidence, and daily Garmin Z-scores as JSON.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        // MARK: - Helpers

        private func infoRow(icon: String, color: Color, title: String, desc: String) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(desc).font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        private func iconColor(for key: SmartSenseWeights.FactorKey) -> Color {
            switch key {
            case .sleepScore, .sleepDuration: return .indigo
            case .bodyBattery: return .yellow
            case .currentStress, .avgStress: return .purple
            case .restingHRDelta: return .red
            case .hrvDelta: return .orange
            case .yesterdayActivity, .todayActivity: return .green
            case .vigorousExercise: return .pink
            }
        }
    }
}
