import SwiftUI

/// Sheet that lets the user pick what to export from the Statistics screen and generates an A4 PDF.
/// Currently only Data: Glucose, Range: Monthly, Chart Type: Distribution are enabled — the other
/// options are shown but disabled to signal what's coming next.
struct StatExportMenuView: View {
    let state: Stat.StateModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var selectedDataType: Stat.StateModel.StatisticViewType = .glucose
    @State private var selectedRange: Stat.StateModel.StatsTimeInterval = .month
    @State private var selectedGlucoseChartType: Stat.StateModel.GlucoseChartType = .distributionByTime
    @State private var reportName: String = ""

    @State private var isExporting = false
    @State private var exportedPDFURL: URL?
    @State private var showShareSheet = false
    @State private var exportErrorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Data")) {
                    ForEach(Stat.StateModel.StatisticViewType.allCases) { type in
                        optionRow(
                            title: type.displayName,
                            isSelected: selectedDataType == type,
                            isEnabled: type == .glucose
                        ) { selectedDataType = type }
                    }
                }

                Section(header: Text("Range")) {
                    ForEach(Stat.StateModel.StatsTimeInterval.allCases) { interval in
                        optionRow(
                            title: interval.exportDisplayName,
                            isSelected: selectedRange == interval,
                            isEnabled: interval == .month
                        ) { selectedRange = interval }
                    }
                }

                Section(header: Text("Chart Type")) {
                    ForEach(Stat.StateModel.GlucoseChartType.allCases, id: \.self) { type in
                        optionRow(
                            title: type.displayName,
                            isSelected: selectedGlucoseChartType == type,
                            isEnabled: type == .distributionByTime
                        ) { selectedGlucoseChartType = type }
                    }
                }

                Section(header: Text("Report Details"), footer: Text("Optionally add a name to the report header.")) {
                    TextField("Name (optional)", text: $reportName)
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
                        Button("Export") { exportPDF() }
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
            .sheet(isPresented: $showShareSheet, onDismiss: { dismiss() }) {
                if let exportedPDFURL {
                    ShareSheet(activityItems: [exportedPDFURL])
                }
            }
        }
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

    private func exportPDF() {
        isExporting = true
        Task {
            let interval = Stat.StateModel.StatsTimeIntervalWithToday(rawValue: selectedRange.rawValue) ?? .month
            let data = await state.prepareGlucoseDistributionExportData(for: interval)

            let reportView = StatPDFReportView(
                reportName: reportName.trimmingCharacters(in: .whitespacesAndNewlines),
                rangeDisplayName: selectedRange.exportDisplayName,
                periodStart: Date.oneMonthAgo,
                periodEnd: Date(),
                generatedAt: Date(),
                glucose: data.glucose,
                glucoseRangeStats: data.rangeStats,
                highLimit: state.highLimit,
                lowLimit: state.lowLimit,
                units: state.units,
                eA1cDisplayUnit: state.eA1cDisplayUnit,
                timeInRangeType: state.timeInRangeType
            )

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "Trio-Statistics-\(formatter.string(from: Date()))"

            do {
                let url = try StatPDFExporter.export(reportView, fileName: fileName)
                exportedPDFURL = url
                isExporting = false
                showShareSheet = true
            } catch {
                exportErrorMessage = error.localizedDescription
                isExporting = false
            }
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
}
