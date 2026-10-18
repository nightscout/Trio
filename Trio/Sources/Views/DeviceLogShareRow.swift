import SwiftUI

struct DeviceLogShareRow: View {
    let title: String
    let footnote: String
    let pluginIdentifier: String
    let exporter: DeviceLogExporting

    @State private var isExporting = false
    @State private var archiveURL: URL?
    @State private var showShareSheet = false
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

    static let window: TimeInterval = 3 * 24 * 60 * 60

    static func request(for pluginIdentifier: String, endingAt date: Date) -> DeviceLogExportRequest {
        DeviceLogExportRequest(
            window: DateInterval(start: date.addingTimeInterval(-window), end: date),
            managerIdentifier: pluginIdentifier,
            includeOSLog: true,
            includeKitFiles: true
        )
    }

    private static func archiveName(for pluginIdentifier: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "Trio-\(pluginIdentifier)-\(formatter.string(from: date))"
    }

    var body: some View {
        VStack(alignment: .leading) {
            Button {
                share()
            } label: {
                HStack {
                    Text(title)
                        .foregroundColor(.primary)
                    Spacer()
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(isExporting)

            Text(footnote)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .sheet(isPresented: $showShareSheet, onDismiss: removeArchive) {
            if let archiveURL {
                ShareSheet(activityItems: [archiveURL])
            }
        }
        .alert("Export Error", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private func share() {
        guard !isExporting else { return }
        isExporting = true
        let now = Date()
        let request = Self.request(for: pluginIdentifier, endingAt: now)
        let name = Self.archiveName(for: pluginIdentifier, at: now)
        let exporter = self.exporter

        Task { @MainActor in
            defer { isExporting = false }
            do {
                archiveURL = try await LogShareAction.archive(named: name) { directory in
                    try await exporter.export(request, into: directory)
                }
                showShareSheet = true
            } catch {
                exportErrorMessage = error.localizedDescription
                showExportError = true
            }
        }
    }

    private func removeArchive() {
        guard let archiveURL else { return }
        self.archiveURL = nil
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: archiveURL)
        }
    }
}
