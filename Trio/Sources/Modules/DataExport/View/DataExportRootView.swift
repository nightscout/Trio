import SwiftUI
import Swinject

extension DataExport {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("Export Range"),
                    footer: Text("Select how much historical data to include in the export.")
                ) {
                    Picker("Time Range", selection: $state.selectedRange) {
                        ForEach(DataExportService.ExportRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Exported Data"),
                    footer: Text(
                        "Exports CSV files for: glucose readings, carb entries, insulin boluses, temp basal rates, algorithm decisions (IOB, COB, ISF, targets), and total daily dose."
                    )
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Glucose Readings", systemImage: "drop.fill")
                        Label("Carb / Fat / Protein Entries", systemImage: "fork.knife")
                        Label("Insulin Boluses (incl. SMBs)", systemImage: "syringe.fill")
                        Label("Temp Basal Rates", systemImage: "chart.bar.fill")
                        Label("Algorithm Decisions", systemImage: "brain")
                        Label("Total Daily Dose", systemImage: "sum")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.chart)

                Section {
                    Button(action: state.exportData) {
                        HStack {
                            Spacer()
                            if state.isExporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Exporting...")
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export & Share")
                            }
                            Spacer()
                        }
                        .font(.headline)
                    }
                    .disabled(state.isExporting)
                }
                .listRowBackground(Color.chart)

                if let error = state.exportError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .listRowBackground(Color.chart)
                }
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("Export Data")
            .navigationBarTitleDisplayMode(.automatic)
            .sheet(isPresented: $state.showShareSheet) {
                if let url = state.exportedURL {
                    DataExportShareSheet(url: url)
                }
            }
        }
    }
}

/// Shares the combined export file via the system share sheet.
private struct DataExportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
