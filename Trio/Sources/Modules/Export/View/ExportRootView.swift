import SwiftUI
import Swinject

extension Export {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var showSettingsExport = false
        @State private var showExportError = false
        @State private var exportErrorMessage = ""
        @State private var exportedFileURL: URL?

        var body: some View {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export Settings")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(
                            "Choose which categories to export to a CSV file for backup or sharing with your healthcare provider."
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section(
                    header: Text("Export Categories"),
                    footer: Text("Select which categories to include in your export. All categories are enabled by default.")
                ) {
                    // Select All toggle
                    HStack {
                        Button(action: {
                            state.toggleAllCategories(!state.allCategoriesSelected)
                        }) {
                            HStack {
                                Image(systemName: state.allCategoriesSelected ? "checkmark.square.fill" : "square")
                                    .foregroundColor(state.allCategoriesSelected ? .blue : .secondary)
                                Text("Select All")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Individual category toggles
                    ForEach(Export.StateModel.ExportCategory.allCases) { category in
                        HStack {
                            Button(action: {
                                if state.selectedCategories.contains(category) {
                                    state.selectedCategories.remove(category)
                                } else {
                                    state.selectedCategories.insert(category)
                                }
                            }) {
                                HStack {
                                    Image(
                                        systemName: state.selectedCategories
                                            .contains(category) ? "checkmark.square.fill" : "square"
                                    )
                                    .foregroundColor(state.selectedCategories.contains(category) ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        Text(category.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section(
                    header: Text("Export Options"),
                    footer: Text(
                        "Export your selected categories to a CSV file for backup or sharing with your healthcare provider."
                    )
                ) {
                    Button {
                        Task {
                            switch await state.exportSelectedSettings() {
                            case let .success(fileURL):
                                // Verify the file actually exists before showing share sheet
                                if FileManager.default.fileExists(atPath: fileURL.path) {
                                    // Check file size to ensure it's not empty
                                    do {
                                        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                                        let fileSize = attributes[.size] as? Int ?? 0
                                        print("Export file size: \(fileSize) bytes at \(fileURL.path)")

                                        if fileSize > 0 {
                                            exportedFileURL = fileURL
                                            showSettingsExport = true
                                        } else {
                                            exportErrorMessage = "Export file is empty (0 bytes)"
                                            showExportError = true
                                        }
                                    } catch {
                                        exportErrorMessage =
                                            "Could not verify file attributes: \(error.localizedDescription)"
                                        showExportError = true
                                    }
                                } else {
                                    exportErrorMessage =
                                        "Export file was created but could not be found at: \(fileURL.path)"
                                    showExportError = true
                                }
                            case let .failure(error):
                                exportErrorMessage = error.localizedDescription
                                showExportError = true
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export Selected Categories")
                                    .foregroundColor(.primary)
                                if state.selectedCategories.count < Export.StateModel.ExportCategory.allCases.count {
                                    Text(
                                        "\(state.selectedCategories.count) of \(Export.StateModel.ExportCategory.allCases.count) categories selected"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .disabled(state.selectedCategories.isEmpty)
                }

                Section(
                    header: Text("Export Information"),
                    footer: Text(
                        "Exported files contain data from your selected categories. Choose specific categories above to customize what gets exported."
                    )
                ) {
                    HStack {
                        Text("Format")
                        Spacer()
                        Text("CSV")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Includes")
                        Spacer()
                        Text("\(state.selectedCategories.count) Selected Categories")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("File Name")
                        Spacer()
                        Text("TrioSettings_[timestamp].csv")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSettingsExport) {
                if let fileURL = exportedFileURL {
                    ExportShareSheet(activityItems: [fileURL])
                }
            }
            .alert("Export Error", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage)
            }
        }
    }
}

private struct ExportCategoryRow: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct ExportShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
