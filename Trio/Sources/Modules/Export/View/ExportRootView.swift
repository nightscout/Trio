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

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("Export Categories"),
                    content: {
                        // Select All toggle
                        HStack {
                            Button(action: {
                                state.toggleAllCategories(!state.allCategoriesSelected)
                            }) {
                                HStack {
                                    Image(systemName: state.allCategoriesSelected ? "checkmark.square.fill" : "square")
                                        .foregroundColor(state.allCategoriesSelected ? .blue : .secondary)
                                    Text("Select All")
                                        .fontWeight(.bold)
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

                                        Text(category.rawValue)

                                        Spacer()
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 2)
                        }
                    }
                ).listRowBackground(Color.chart)

                Section(
                    header: Text("Export Information"),
                    content: {
                        Picker(
                            selection: $state.selectedFormat,
                            label: Text("Format").multilineTextAlignment(.leading)
                        ) {
                            ForEach(Export.StateModel.ExportFormat.allCases) { selection in
                                Text(selection.fileExtension).tag(selection)
                            }
                        }

                        HStack {
                            Text("Content")
                            Spacer()
                            Text("\(state.selectedCategories.count) Selected Categories")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("File Name")
                            Spacer()
                            Text("TrioSettings_[timestamp].\(state.selectedFormat.fileExtension)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                ).listRowBackground(Color.chart)
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Export Settings")
            .navigationBarTitleDisplayMode(.automatic)
//            .toolbar {
//                ToolbarItem(placement: .topBarTrailing) {
//                    if state.isExporting {
//                        HStack(spacing: 8) {
//                            ProgressView()
//                                .scaleEffect(0.8)
//                            Text("Exporting...")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                        }
//                    } else {
//                        Button("Export") {
//                            Task {
//                                print("🚀 UI: Export button tapped")
//                                // Start loading spinner
//                                state.isExporting = true
//                                print("🚀 UI: Loading spinner started")
//
//                                switch await state.exportSelectedSettings() {
//                                case let .success(fileURL):
//                                    print("✅ UI: Export returned success with URL: \(fileURL)")
//                                    if FileManager.default.fileExists(atPath: fileURL.path) {
//                                        do {
//                                            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
//                                            let fileSize = attributes[.size] as? Int ?? 0
//                                            print("📊 UI: Export file size: \(fileSize) bytes at \(fileURL.path)")
//
//                                            if fileSize > 0 {
//                                                print("✅ UI: File validation passed, setting up share sheet")
//                                                exportedFileURL = fileURL
//                                                // Stop spinner on successful export
//                                                state.isExporting = false
//                                                print("🔄 UI: Loading spinner stopped")
//                                                showSettingsExport = true
//                                                print("📤 UI: Share sheet triggered")
//                                            } else {
//                                                print("❌ UI: File is empty")
//                                                exportErrorMessage = "Export file is empty (0 bytes)"
//                                                showExportError = true
//                                                // Stop spinner on error
//                                                state.isExporting = false
//                                            }
//                                        } catch {
//                                            print("❌ UI: Could not verify file attributes: \(error)")
//                                            exportErrorMessage = "Could not verify file attributes: \(error.localizedDescription)"
//                                            showExportError = true
//                                            // Stop spinner on error
//                                            state.isExporting = false
//                                        }
//                                    } else {
//                                        print("❌ UI: File does not exist at expected path: \(fileURL.path)")
//                                        exportErrorMessage = "Export file was created but could not be found at: \(fileURL.path)"
//                                        showExportError = true
//                                        // Stop spinner on error
//                                        state.isExporting = false
//                                    }
//                                case let .failure(error):
//                                    print("❌ UI: Export failed with error: \(error)")
//                                    exportErrorMessage = error.localizedDescription
//                                    showExportError = true
//                                    // Stop spinner on error
//                                    state.isExporting = false
//                                }
//                            }
//                        }
//                        .disabled(state.selectedCategories.isEmpty)
//                    }
//                }
//            }
            .sheet(isPresented: $showSettingsExport) {
                if let fileURL = exportedFileURL {
                    ShareSheet(activityItems: [fileURL])
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
