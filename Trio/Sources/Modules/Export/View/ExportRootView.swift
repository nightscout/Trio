// ABOUTME: Export module root view for settings export functionality
// ABOUTME: Provides dedicated UI for comprehensive settings export

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
                        
                        Text("Export all your Trio settings to a CSV file for backup or sharing with your healthcare provider.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                Section(
                    header: Text("Export Options"),
                    footer: Text("The export includes app settings, therapy profiles, algorithm configuration, device settings, and preset data.")
                ) {
                    Button {
                        Task {
                            switch await state.exportSettings() {
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
                            Text("Export All Settings")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
                
                Section(
                    header: Text("Export Information"),
                    footer: Text("Exported files contain comprehensive configuration data including therapy profiles, algorithm settings, device configurations, and preset data.")
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
                        Text("All Settings")
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
                
                Section(
                    header: Text("Export Categories"),
                    footer: Text("Each export includes data from all of these categories to provide a complete backup of your Trio configuration.")
                ) {
                    ExportCategoryRow(
                        title: "Export Info",
                        description: "Date, app version, build information"
                    )
                    ExportCategoryRow(
                        title: "Devices",
                        description: "CGM and pump configuration"
                    )
                    ExportCategoryRow(
                        title: "Therapy",
                        description: "Basal profiles, ISF, carb ratios, targets"
                    )
                    ExportCategoryRow(
                        title: "Algorithm",
                        description: "SMB, autosens, dynamic settings"
                    )
                    ExportCategoryRow(
                        title: "Features",
                        description: "UI preferences, meal settings"
                    )
                    ExportCategoryRow(
                        title: "Notifications",
                        description: "Alert and notification settings"
                    )
                    ExportCategoryRow(
                        title: "Services",
                        description: "Nightscout, Apple Health integration"
                    )
                    ExportCategoryRow(
                        title: "Presets",
                        description: "Temp targets, overrides, meal presets"
                    )
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.large)
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

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}