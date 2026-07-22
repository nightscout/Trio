import SwiftUI

/// Sheet that lets the user build a multi-page PDF report from the Statistics screen: add one or
/// more (Data type, Chart type) combinations to a working list, sharing a single date Range, then
/// export them all as one PDF (one page per item). Combinations can be saved as a named preset for
/// reuse (e.g. a recurring clinician-visit report) and reloaded later; only the chart types still
/// shown as "Coming soon" on the live Statistics screen (Looping's CGM Connection Trace / Trio
/// Up-Time, Meals' Meal to Hypo/Hyper) stay disabled here too.
struct StatExportMenuView: View {
    let state: Stat.StateModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var selectedDataType: Stat.StateModel.StatisticViewType = .glucose
    @State private var selectedRange: Stat.StateModel.StatsTimeInterval = .month
    @State private var selectedGlucoseChartType: Stat.StateModel.GlucoseChartType = .distributionByTime
    @State private var selectedInsulinChartType: Stat.StateModel.InsulinChartType = .totalDailyDose
    @State private var selectedLoopingChartType: Stat.StateModel.LoopingChartType = .loopingPerformance
    @State private var selectedMealChartType: Stat.StateModel.MealChartType = .totalMeals
    @State private var reportName: String = ""

    @State private var reportItems: [ReportChartType] = []
    @State private var savedPresets: [ReportPreset] = []
    @State private var presetToDelete: ReportPreset?
    @State private var showSavePresetPrompt = false
    @State private var presetNameInput: String = ""

    @State private var isExporting = false
    @State private var exportedPDFURL: URL?
    @State private var showShareSheet = false
    @State private var exportErrorMessage: String?
    @State private var showInfo = false

    var body: some View {
        NavigationView {
            Form {
                if !savedPresets.isEmpty {
                    savedReportsSection
                }

                Section(header: Text("Range")) {
                    ForEach(Stat.StateModel.StatsTimeInterval.allCases) { interval in
                        optionRow(
                            title: interval.exportDisplayName,
                            isSelected: selectedRange == interval,
                            isEnabled: isRangeEnabled(interval)
                        ) { selectedRange = interval }
                    }
                }

                addChartSection

                reportItemsSection

                Section(
                    header: Text("Report Details"),
                    footer: Text("Optionally add a patient name to the report header.")
                ) {
                    TextField("Patient name (optional)", text: $reportName)

                    Button("Save as Preset…") {
                        // Presets are a reusable chart/range template, not tied to one patient,
                        // so don't seed the prompt with the patient name typed above.
                        presetNameInput = ""
                        showSavePresetPrompt = true
                    }
                    .disabled(reportItems.isEmpty)
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Export Stats to PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Button(exportButtonTitle) { exportPDF() }
                            .disabled(reportItems.isEmpty)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "questionmark.circle")
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
            .sheet(isPresented: $showInfo) {
                StatExportMenuInfoView(isPresented: $showInfo)
            }
        }
        .onAppear {
            savedPresets = state.loadReportPresets()
        }
        .onChange(of: selectedGlucoseChartType) { _, newValue in
            // A single-day box/bar plot isn't meaningful, so bump off the "Day" range —
            // mirrors the same restriction already enforced on the live Statistics screen.
            if newValue == .percentileByDay || newValue == .distributionByDay, selectedRange == .day {
                selectedRange = .week
            }
        }
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
        // one leaves the Patient name field alone.
        selectedRange = preset.range
        reportItems = preset.chartTypes
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

        let preset = ReportPreset(name: trimmedName, range: selectedRange, chartTypes: reportItems)
        state.saveReportPreset(preset)
        savedPresets = state.loadReportPresets()
    }

    // MARK: - Report Items

    /// Hidden entirely until the first chart is added — an empty list with instructional text
    /// reads as one more thing to parse, whereas a section that simply appears once there's
    /// something in it doubles as its own confirmation that "Add to Report" worked.
    @ViewBuilder private var reportItemsSection: some View {
        if !reportItems.isEmpty {
            Section(header: Text("Report Items (\(reportItems.count))")) {
                ForEach(reportItems) { item in
                    HStack {
                        Text(item.dataType.displayName)
                            .foregroundStyle(Color.secondary)
                        Text("·")
                            .foregroundStyle(Color.secondary)
                        Text(item.displayName)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            reportItems.removeAll { $0 == item }
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                        .tint(.red)
                    }
                }
                .onMove { indices, newOffset in
                    reportItems.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
        }
    }

    private var exportButtonTitle: String {
        reportItems.isEmpty ? String(localized: "Export") : String(localized: "Export (\(reportItems.count))")
    }

    /// The `ReportChartType` corresponding to whatever is currently staged in the Data/Chart Type
    /// pickers below, or `nil` if the staged chart type isn't exportable yet ("Coming soon").
    private var currentSelection: ReportChartType? {
        switch selectedDataType {
        case .glucose:
            switch selectedGlucoseChartType {
            case .distributionByTime: return .glucoseDistributionByTime
            case .percentileByTime: return .glucosePercentileByTime
            case .percentileByDay: return .glucosePercentileByDay
            case .distributionByDay: return .glucoseDistributionByDay
            }
        case .insulin:
            switch selectedInsulinChartType {
            case .totalDailyDose: return .insulinTotalDailyDose
            case .bolusDistribution: return .insulinBolusDistribution
            }
        case .looping:
            return selectedLoopingChartType == .loopingPerformance ? .loopingPerformance : nil
        case .meals:
            return selectedMealChartType == .totalMeals ? .mealsTotalMeals : nil
        }
    }

    private var isCurrentSelectionAdded: Bool {
        currentSelection.map(reportItems.contains) ?? false
    }

    private func addCurrentSelectionToReport() {
        guard let selection = currentSelection, !reportItems.contains(selection) else { return }
        reportItems.append(selection)
    }

    // MARK: - Add Chart

    /// Data type, Chart type, and the "Add to Report" action all live in one section so the
    /// relationship between picking a combination and adding it is visible at a glance, instead
    /// of being split across separate Form sections with the button that acts on them floating
    /// on its own underneath.
    private var addChartSection: some View {
        Section(header: Text("Add a Chart")) {
            subHeader("Data")
            ForEach(Stat.StateModel.StatisticViewType.allCases) { type in
                optionRow(
                    title: type.displayName,
                    isSelected: selectedDataType == type,
                    isEnabled: true
                ) { selectedDataType = type }
            }

            subHeader("Chart Type")
            chartTypeRows

            Button {
                addCurrentSelectionToReport()
            } label: {
                HStack {
                    Text("Add to Report")
                    Spacer()
                    if isCurrentSelectionAdded {
                        Text("Added")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .disabled(currentSelection == nil || isCurrentSelectionAdded)
        }
    }

    private func subHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color.secondary)
            .padding(.top, 4)
    }

    @ViewBuilder private var chartTypeRows: some View {
        switch selectedDataType {
        case .glucose:
            ForEach(Stat.StateModel.GlucoseChartType.allCases, id: \.self) { type in
                optionRow(
                    title: type.displayName,
                    isSelected: selectedGlucoseChartType == type,
                    isEnabled: true
                ) { selectedGlucoseChartType = type }
            }
        case .insulin:
            ForEach(Stat.StateModel.InsulinChartType.allCases, id: \.self) { type in
                optionRow(
                    title: type.displayName,
                    isSelected: selectedInsulinChartType == type,
                    isEnabled: true
                ) { selectedInsulinChartType = type }
            }
        case .looping:
            ForEach(Stat.StateModel.LoopingChartType.allCases, id: \.self) { type in
                optionRow(
                    title: type.displayName,
                    isSelected: selectedLoopingChartType == type,
                    isEnabled: type == .loopingPerformance
                ) { selectedLoopingChartType = type }
            }
        case .meals:
            ForEach(Stat.StateModel.MealChartType.allCases, id: \.self) { type in
                optionRow(
                    title: type.displayName,
                    isSelected: selectedMealChartType == type,
                    isEnabled: type == .totalMeals
                ) { selectedMealChartType = type }
            }
        }
    }

    /// A single-day box/bar plot isn't meaningful for the by-day glucose charts, so the "Day"
    /// range is disabled whenever the working report contains one — same restriction already
    /// enforced on the live Statistics screen (`StatRootView.intervalOptions`).
    private func isRangeEnabled(_ interval: Stat.StateModel.StatsTimeInterval) -> Bool {
        guard interval == .day else { return true }
        return !reportItems.contains(.glucosePercentileByDay) && !reportItems.contains(.glucoseDistributionByDay)
    }

    @ViewBuilder private func optionRow(
        title: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                Spacer()
                if !isEnabled {
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(!isEnabled)
    }

    // MARK: - Export

    private func exportPDF() {
        isExporting = true
        Task { @MainActor in
            let reportMetadata = state.prepareReportMetadata()
            let trimmedReportName = reportName.trimmingCharacters(in: .whitespacesAndNewlines)
            let periodStart = selectedRange.periodStart
            let periodEnd = Date()
            let widenedInterval = Stat.StateModel.StatsTimeIntervalWithToday(rawValue: selectedRange.rawValue) ?? .month

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "Trio-Statistics-\(formatter.string(from: Date()))"

            var pages: [AnyView] = []
            for item in reportItems {
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
        let dataTypeDisplayName = chartType.dataType.displayName
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
