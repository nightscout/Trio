import SwiftUI
import Swinject

extension SettingsExport {
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
                                    Text(
                                        state
                                            .allCategoriesSelected ? String(localized: "Deselect All") :
                                            String(localized: "Select All")
                                    )
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Individual category toggles
                        ForEach(SettingsExport.StateModel.ExportCategory.allCases) { category in
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

                Section {
                    Button(action: {
                        Task {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.isExporting = true

                            switch await state.exportSelectedSettings() {
                            case let .success(fileURL):
                                if FileManager.default.fileExists(atPath: fileURL.path) {
                                    do {
                                        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                                        let fileSize = attributes[.size] as? Int ?? 0

                                        if fileSize > 0 {
                                            exportedFileURL = fileURL
                                            // Stop spinner on successful export
                                            state.isExporting = false
                                            showSettingsExport = true
                                        } else {
                                            exportErrorMessage = "Export file is empty (0 bytes)"
                                            showExportError = true
                                            state.isExporting = false
                                        }
                                    } catch {
                                        exportErrorMessage = "Could not verify file attributes: \(error.localizedDescription)"
                                        showExportError = true
                                        // Stop spinner on error
                                        state.isExporting = false
                                    }
                                } else {
                                    exportErrorMessage = "Export file was created but could not be found at: \(fileURL.path)"
                                    showExportError = true
                                    // Stop spinner on error
                                    state.isExporting = false
                                }
                            case let .failure(error):
                                exportErrorMessage = error.localizedDescription
                                showExportError = true
                                // Stop spinner on error
                                state.isExporting = false
                            }
                        }
                    }, label: {
                        if state.isExporting {
                            HStack {
                                ProgressView().padding(.trailing, 10)
                                Text("Exporting...")
                            }
                        } else {
                            Text("Export Settings")
                        }

                    })
                        .disabled(state.selectedCategories.isEmpty)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                }.listRowBackground(
                    state.selectedCategories.isEmpty ? Color(.systemGray4) : Color(.systemBlue)
                )
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Export Settings")
            .navigationBarTitleDisplayMode(.automatic)
//            // TODO: implement help sheet
//            .toolbar {
//                ToolbarItem(placement: .topBarTrailing) {
//                    Button(
//                        action: {
//                            state.isHelpSheetPresented.toggle()
//                        },
//                        label: {
//                            Image(systemName: "questionmark.circle")
//                        }
//                    )
//                }
//            }
//            .sheet(isPresented: $state.isHelpSheetPresented) {
//                NavigationStack {
//                    List {
//                        Text("Hello World!")
//                    }
//                }
//                .padding()
//                .presentationDetents(
//                    [.fraction(0.9), .large],
//                    selection: $state.helpSheetDetent
//                )
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
