import SwiftUI

/// Builds a multi-page PDF report from the Statistics screen. Each enabled chart becomes
/// one page, in list order, over a shared date range. Selections can be saved as presets.
struct StatExportMenuView: View {
    let state: Stat.StateModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var selectedRange: Stat.StateModel.StatsTimeInterval = .month

    /// Last patient name used, to prefill the export prompt.
    @State private var patientName: String = ""
    @State private var showPatientNamePrompt = false
    @State private var patientNameInput: String = ""

    /// Categories currently expanded to show their charts.
    @State private var expandedCategories: Set<ReportCategory> = []
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
                        // Presets aren't tied to a patient, so don't prefill the name.
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
                            // Ask for the patient name on every export, prefilled with the last one.
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
        // Presets don't include a patient name, so leave it unchanged.
        withAnimation {
            selectedCharts = Set(preset.chartTypes)
            expandedCategories = Set(preset.chartTypes.map(\.category))
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

    /// Same D / W / M / 3 M picker as the Statistics screen.
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

    /// Per-day charts are disabled for the single-day range but stay selected, so a longer
    /// range restores them.
    private func isAvailable(_ chart: ReportChartType) -> Bool {
        !(selectedRange == .day && chart.isPerDay)
    }

    // MARK: - Include in Report

    /// Indent for chart rows under their data type.
    private static let chartRowInset: CGFloat = 20

    /// One expandable row per category with a toggle per chart. Collapsed rows show the
    /// selected count.
    private var includeInReportSection: some View {
        Section(
            header: Text("Include"),
            footer: Group {
                if orderedSelectedCharts.contains(where: { !$0.usesDateRange }) {
                    Text("Therapy settings show the current schedules. The range doesn't apply to them.")
                }
            }
        ) {
            ForEach(ReportCategory.exportOrder) { category in
                categoryRow(for: category)

                if expandedCategories.contains(category) {
                    ForEach(chartOptions(for: category), id: \.title) { option in
                        chartRow(title: option.title, chart: option.chart)
                    }
                }
            }
        }
    }

    private func categoryRow(for category: ReportCategory) -> some View {
        let isExpanded = expandedCategories.contains(category)
        let selectedCount = orderedSelectedCharts.filter { $0.category == category }.count

        return Button {
            withAnimation {
                if isExpanded {
                    expandedCategories.remove(category)
                } else {
                    expandedCategories.insert(category)
                }
            }
        } label: {
            HStack {
                Text(category.displayName)
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

    /// All chart types the Statistics screen offers for `category`, in order. `chart` is `nil`
    /// for ones not exportable yet.
    private func chartOptions(for category: ReportCategory) -> [(title: String, chart: ReportChartType?)] {
        switch category {
        case .glucose:
            return Stat.StateModel.GlucoseChartType.allCases.map { ($0.displayName, ReportChartType($0)) }
        case .insulin:
            return Stat.StateModel.InsulinChartType.allCases.map { ($0.displayName, ReportChartType($0)) }
        case .looping:
            return Stat.StateModel.LoopingChartType.allCases.map { ($0.displayName, ReportChartType($0)) }
        case .meals:
            return Stat.StateModel.MealChartType.allCases.map { ($0.displayName, ReportChartType($0)) }
        case .therapySettings:
            return ReportChartType.therapySettings.map { ($0.displayName, $0) }
        }
    }

    /// Selected charts available for the current range, in page order.
    private var orderedSelectedCharts: [ReportChartType] {
        ReportCategory.exportOrder
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

    /// Builds one PDF page for a report item.
    @MainActor private func buildPage(
        for chartType: ReportChartType,
        widenedInterval: Stat.StateModel.StatsTimeIntervalWithToday,
        trimmedReportName: String,
        reportMetadata: Stat.StateModel.ReportMetadata,
        periodStart: Date,
        periodEnd: Date
    ) async -> AnyView {
        let dataTypeDisplayName = chartType.category.displayName
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
                showsDateRange: chartType.usesDateRange,
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

        case .therapyBasalRates:
            let data = state.prepareTherapyScheduleExportData(for: .basalRates)
            return AnyView(page { TherapySchedulePDFContent(data: data) })

        case .therapyGlucoseTargets:
            let data = state.prepareTherapyScheduleExportData(for: .glucoseTargets)
            return AnyView(page { TherapySchedulePDFContent(data: data) })

        case .therapyCarbRatios:
            let data = state.prepareTherapyScheduleExportData(for: .carbRatios)
            return AnyView(page { TherapySchedulePDFContent(data: data) })

        case .therapyInsulinSensitivities:
            let data = state.prepareTherapyScheduleExportData(for: .insulinSensitivities)
            return AnyView(page { TherapySchedulePDFContent(data: data) })
        }
    }
}

extension Stat.StateModel.StatsTimeInterval {
    /// Full-word name for the export menu and PDF header. `displayName` is the short picker label.
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

    /// Start of this range, using the same offsets as the stats predicates
    /// (e.g. `NSPredicate.glucoseForStatsWeek`) so the header matches the fetched data.
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
