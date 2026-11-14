import SwiftUI

/// Sheet that lets the user build a multi-page PDF report from the Statistics screen. Each data
/// type (Glucose, Carbs, Insulin, Looping) is a row that expands on tap to reveal its chart types,
/// each with its own toggle. Every enabled chart becomes one PDF page, in the same order they're
/// listed, all sharing a single date Range. Selections can be saved as a named preset for reuse
/// (e.g. a recurring clinician-visit report) and reloaded later; only the chart types still shown
/// as "Coming soon" on the live Statistics screen (Looping's CGM Connection Trace / Trio Up-Time,
/// Meals' Meal to Hypo/Hyper) stay disabled here too.
struct StatExportMenuView: View {
    let state: Stat.StateModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var selectedRange: Stat.StateModel.StatsTimeInterval = .month

    /// The last patient name used, persisted so the prompt shown on each export comes prefilled.
    @State private var patientName: String = ""
    @State private var showPatientNamePrompt = false
    @State private var patientNameInput: String = ""

    /// Data types currently expanded to show their charts.
    @State private var expandedDataTypes: Set<Stat.StateModel.StatisticViewType> = []
    @State private var selectedCharts: Set<ReportChartType> = []
    @State private var savedPresets: [ReportPreset] = []
    @State private var presetToDelete: ReportPreset?
    @State private var showSavePresetPrompt = false
    @State private var presetNameInput: String = ""

    @State private var isExporting = false
    @State private var exportedPDFURL: URL?
    @State private var showShareSheet = false
    @State private var exportErrorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                if !savedPresets.isEmpty {
                    savedReportsSection
                }

                rangeSection

                includeInReportSection

                Section {
                    Button("Save as Preset…") {
                        // Presets are a reusable chart/range template, not tied to a patient,
                        // so don't seed the prompt with the patient name.
                        presetNameInput = ""
                        showSavePresetPrompt = true
                    }
                    .disabled(orderedSelectedCharts.isEmpty)
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Export PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Button("Export") {
                            // Confirm the patient name on every export, prefilled with the last one.
                            patientNameInput = patientName
                            showPatientNamePrompt = true
                        }
                        .disabled(orderedSelectedCharts.isEmpty)
                    }
                }
            }
            .alert(
                "Export Failed",
                isPresented: Binding(get: { exportErrorMessage != nil }, set: { if !$0 { exportErrorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "")
            }
            .alert("Save Report Preset", isPresented: $showSavePresetPrompt) {
                TextField("Preset name", text: $presetNameInput)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveCurrentSelectionAsPreset() }
            } message: {
                Text("Saves the current range and chart selection for reuse.")
            }
            .alert("Patient Name", isPresented: $showPatientNamePrompt) {
                TextField("Name", text: $patientNameInput)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Export") {
                    savePatientName(patientNameInput)
                    exportPDF()
                }
            } message: {
                Text("Shown in the report header. Leave blank to omit.")
            }
            .confirmationDialog(
                String(
                    localized: "Delete the report preset \"\(presetToDelete?.name ?? "")\"?",
                    comment: "Delete confirmation title for report presets"
                ),
                isPresented: Binding(get: { presetToDelete != nil }, set: { if !$0 { presetToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { confirmDeletePreset() }
                Button("Cancel", role: .cancel) { presetToDelete = nil }
            }
            .sheet(isPresented: $showShareSheet, onDismiss: { dismiss() }) {
                if let exportedPDFURL {
                    ShareSheet(activityItems: [exportedPDFURL])
                }
            }
        }
        .onAppear {
            savedPresets = state.loadReportPresets()
            patientName = state.loadReportPatientName() ?? ""
        }
    }

    // MARK: - Patient Name

    private func savePatientName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        patientName = trimmed
        state.saveReportPatientName(trimmed)
    }

    // MARK: - Saved Reports

    private var savedReportsSection: some View {
        Section(header: Text("Saved Reports")) {
            ForEach(savedPresets) { preset in
                Button {
                    loadPreset(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                            .foregroundStyle(Color.primary)
                        Text("\(preset.range.exportDisplayName) · \(chartCountText(preset.chartTypes.count))")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        presetToDelete = preset
                    } label: {
                        Label("Delete", systemImage: "trash.fill")
                    }
                    .tint(.red)
                }
            }
        }
    }

    private func chartCountText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 chart") : String(localized: "\(count) charts")
    }

    private func loadPreset(_ preset: ReportPreset) {
        // A preset is just a reusable range/chart template, not tied to a patient, so loading
        // one leaves the patient name alone.
        withAnimation {
            selectedCharts = Set(preset.chartTypes)
            expandedDataTypes = Set(preset.chartTypes.map(\.dataType))
            selectedRange = preset.range
        }
    }

    private func confirmDeletePreset() {
        if let preset = presetToDelete {
            state.deleteReportPreset(preset)
            savedPresets = state.loadReportPresets()
        }
        presetToDelete = nil
    }

    private func saveCurrentSelectionAsPreset() {
        let trimmedName = presetNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let preset = ReportPreset(name: trimmedName, range: selectedRange, chartTypes: orderedSelectedCharts)
        state.saveReportPreset(preset)
        savedPresets = state.loadReportPresets()
    }

    // MARK: - Range

    /// Same segmented D / W / M / 3 M control the Statistics screen uses for its Duration picker.
    private var rangeSection: some View {
        Section(header: Text("Range")) {
            Picker("Range", selection: $selectedRange) {
                ForEach(Stat.StateModel.StatsTimeInterval.allCases) { interval in
                    Text(interval.displayName).tag(interval)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    /// Per-day charts are unavailable for the single-day range. They stay in `selectedCharts` while
    /// disabled, so switching back to a longer range restores them.
    private func isAvailable(_ chart: ReportChartType) -> Bool {
        !(selectedRange == .day && chart.isPerDay)
    }

    // MARK: - Include in Report

    /// How far chart rows are indented under their data type's row.
    private static let chartRowInset: CGFloat = 20

    /// A single group: one row per data type that expands on tap to list that type's chart types
    /// directly beneath it, indented, each with its own toggle. Inclusion is decided purely by the
    /// chart toggles; collapsed rows show how many charts are selected.
    private var includeInReportSection: some View {
        Section(header: Text("Include")) {
            ForEach(Stat.StateModel.StatisticViewType.exportOrder) { dataType in
                categoryRow(for: dataType)

                if expandedDataTypes.contains(dataType) {
                    ForEach(chartOptions(for: dataType), id: \.title) { option in
                        chartRow(title: option.title, chart: option.chart)
                    }
                }
            }
        }
    }

    private func categoryRow(for dataType: Stat.StateModel.StatisticViewType) -> some View {
        let isExpanded = expandedDataTypes.contains(dataType)
        let selectedCount = orderedSelectedCharts.filter { $0.dataType == dataType }.count

        return Button {
            withAnimation {
                if isExpanded {
                    expandedDataTypes.remove(dataType)
                } else {
                    expandedDataTypes.insert(dataType)
                }
            }
        } label: {
            HStack {
                Text(dataType.exportDisplayName)
                    .foregroundStyle(Color.primary)
                Spacer()
                if selectedCount > 0 {
                    Text(chartCountText(selectedCount))
                        .foregroundStyle(Color.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
    }

    @ViewBuilder private func chartRow(title: String, chart: ReportChartType?) -> some View {
        if let chart {
            // A disabled Toggle only dims its switch, so grey the title explicitly to match.
            Toggle(isOn: isSelectedBinding(for: chart)) {
                Text(title)
                    .foregroundStyle(isAvailable(chart) ? Color.primary : Color.secondary)
            }
            .disabled(!isAvailable(chart))
            .padding(.leading, Self.chartRowInset)
        } else {
            HStack {
                Text(title)
                    .foregroundStyle(Color.secondary)
                Spacer()
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.leading, Self.chartRowInset)
        }
    }

    private func isSelectedBinding(for chart: ReportChartType) -> Binding<Bool> {
        Binding(
            get: { selectedCharts.contains(chart) && isAvailable(chart) },
            set: { isOn in
                if isOn {
                    selectedCharts.insert(chart)
                } else {
                    selectedCharts.remove(chart)
                }
            }
        )
    }

    /// Every chart type the live Statistics screen offers for `dataType`, in the same order; `chart`
    /// is `nil` for the ones not exportable yet ("Coming soon").
    private func chartOptions(for dataType: Stat.StateModel.StatisticViewType) -> [(title: String, chart: ReportChartType?)] {
        switch dataType {
        case .glucose:
            return Stat.StateModel.GlucoseChartType.allCases.map { ($0.displayName, ReportChartType($0)) }
        case .insulin:
            return Stat.StateModel.InsulinChartType.allCases.map { ($0.displayName, ReportChartType($0)) }
        case .looping:
            return Stat.StateModel.LoopingChartType.allCases.map { ($0.displayName, ReportChartType($0)) }
        case .meals:
            return Stat.StateModel.MealChartType.allCases.map { ($0.displayName, ReportChartType($0)) }
        }
    }

    /// The charts that will actually be exported — selected and available for the current range —
    /// in on-screen order, which is also the PDF page order.
    private var orderedSelectedCharts: [ReportChartType] {
        Stat.StateModel.StatisticViewType.exportOrder
            .flatMap { chartOptions(for: $0).compactMap(\.chart) }
            .filter { selectedCharts.contains($0) && isAvailable($0) }
    }

    // MARK: - Export

    private func exportPDF() {
        isExporting = true
        Task { @MainActor in
            let reportMetadata = state.prepareReportMetadata()
            let trimmedReportName = patientName
            let periodStart = selectedRange.periodStart
            let periodEnd = Date()
            let widenedInterval = Stat.StateModel.StatsTimeIntervalWithToday(rawValue: selectedRange.rawValue) ?? .month

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "Trio-Statistics-\(formatter.string(from: Date()))"

            var pages: [AnyView] = []
            for item in orderedSelectedCharts {
                pages.append(await buildPage(
                    for: item,
                    widenedInterval: widenedInterval,
                    trimmedReportName: trimmedReportName,
                    reportMetadata: reportMetadata,
                    periodStart: periodStart,
                    periodEnd: periodEnd
                ))
            }

            do {
                let url = try StatPDFExporter.export(pages, fileName: fileName)
                exportedPDFURL = url
                isExporting = false
                showShareSheet = true
            } catch {
                exportErrorMessage = error.localizedDescription
                isExporting = false
            }
        }
    }

    /// Builds a single PDF page for one report item: fetches/prepares that chart type's data and
    /// wraps it in the shared `StatPDFPage` header/footer.
    @MainActor private func buildPage(
        for chartType: ReportChartType,
        widenedInterval: Stat.StateModel.StatsTimeIntervalWithToday,
        trimmedReportName: String,
        reportMetadata: Stat.StateModel.ReportMetadata,
        periodStart: Date,
        periodEnd: Date
    ) async -> AnyView {
        let dataTypeDisplayName = chartType.dataType.exportDisplayName
        let chartTypeDisplayName = chartType.displayName

        func page(@ViewBuilder content: () -> some View) -> some View {
            StatPDFPage(
                reportName: trimmedReportName,
                dataTypeDisplayName: dataTypeDisplayName,
                chartTypeDisplayName: chartTypeDisplayName,
                rangeDisplayName: selectedRange.exportDisplayName,
                periodStart: periodStart,
                periodEnd: periodEnd,
                generatedAt: Date(),
                reportMetadata: reportMetadata,
                content: content
            )
        }

        switch chartType {
        case .glucoseDistributionByTime:
            let data = await state.prepareGlucoseDistributionExportData(for: widenedInterval)
            return AnyView(page {
                GlucoseDistributionPDFContent(
                    glucose: data.glucose,
                    glucoseRangeStats: data.rangeStats,
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    eA1cDisplayUnit: state.eA1cDisplayUnit,
                    timeInRangeType: state.timeInRangeType
                )
            })

        case .glucosePercentileByTime:
            let data = await state.preparePercentileExportData(for: widenedInterval)
            return AnyView(page {
                GlucosePercentilePDFContent(
                    glucose: data.glucose,
                    highLimit: state.highLimit,
                    timeInRangeType: state.timeInRangeType,
                    units: state.units,
                    hourlyStats: data.hourlyStats
                )
            })

        case .glucosePercentileByDay:
            let data = await state.prepareGlucosePercentileByDayExportData(for: selectedRange)
            return AnyView(page {
                GlucosePercentileByDayPDFChart(
                    dailyStats: data.dailyStats,
                    highLimit: state.highLimit,
                    units: state.units,
                    timeInRangeType: state.timeInRangeType,
                    selectedInterval: selectedRange
                )
            })

        case .glucoseDistributionByDay:
            let data = await state.prepareGlucoseDistributionByDayExportData(for: selectedRange)
            return AnyView(page {
                GlucoseDistributionByDayPDFChart(
                    dailyStats: data.dailyStats,
                    highLimit: state.highLimit,
                    units: state.units,
                    timeInRangeType: state.timeInRangeType,
                    selectedInterval: selectedRange
                )
            })

        case .glucoseGlycemiaRiskIndex:
            let data = await state.prepareGRIExportData(for: widenedInterval)
            return AnyView(page {
                GlycemiaRiskIndexPDFContent(result: data.result, units: state.units)
            })

        case .insulinTotalDailyDose:
            let data = state.prepareTDDExportData(for: selectedRange)
            return AnyView(page {
                InsulinTDDPDFChart(stats: data.stats, selectedInterval: selectedRange)
            })

        case .insulinBolusDistribution:
            let data = state.prepareBolusExportData(for: selectedRange)
            return AnyView(page {
                InsulinBolusPDFChart(stats: data.stats, selectedInterval: selectedRange)
            })

        case .loopingPerformance:
            let data = await state.prepareLoopingExportData(for: widenedInterval)
            return AnyView(page {
                LoopingPerformancePDFContent(
                    loopStatRecords: data.loopStatRecords,
                    selectedInterval: widenedInterval,
                    loopStats: data.loopStats
                )
            })

        case .mealsTotalMeals:
            let data = state.prepareMealsExportData(for: selectedRange)
            return AnyView(page {
                MealsPDFChart(
                    stats: data.stats,
                    selectedInterval: selectedRange,
                    useFPUconversion: data.useFPUconversion
                )
            })
        }
    }
}

extension Stat.StateModel.StatsTimeInterval {
    /// A full-word display name suitable for the export menu and PDF header
    /// (`displayName` on this type is an abbreviation meant for the segmented picker).
    var exportDisplayName: String {
        switch self {
        case .day:
            return String(localized: "Daily")
        case .week:
            return String(localized: "Weekly")
        case .month:
            return String(localized: "Monthly")
        case .total:
            return String(localized: "3-Month")
        }
    }

    /// The start of this range, using the same fixed offsets as the app's own stats predicates
    /// (e.g. `NSPredicate.glucoseForStatsWeek`), so the PDF header's displayed date range matches
    /// what was actually fetched.
    var periodStart: Date {
        switch self {
        case .day:
            return Date.oneDayAgo
        case .week:
            return Date.oneWeekAgo
        case .month:
            return Date.oneMonthAgo
        case .total:
            return Date.threeMonthsAgo
        }
    }
}

extension Stat.StateModel.StatisticViewType {
    /// Data type order in the export menu, which is also the PDF page order.
    static let exportOrder: [Self] = [.glucose, .meals, .insulin, .looping]

    /// Name used in the export menu and PDF header. Meals reads as "Carbs" here, since that's what
    /// its charts actually report.
    var exportDisplayName: String {
        switch self {
        case .meals:
            return String(localized: "Carbs")
        case .glucose,
             .insulin,
             .looping:
            return displayName
        }
    }
}
