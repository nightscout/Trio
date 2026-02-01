import Foundation
import Observation

extension DataExport {
    @Observable final class StateModel: BaseStateModel<Provider> {
        var selectedRange: DataExportService.ExportRange = .week
        var isExporting: Bool = false
        var exportError: String?
        var exportedURL: URL?
        var showShareSheet: Bool = false

        private let exportService = DataExportService()

        func exportData() {
            guard !isExporting else { return }
            isExporting = true
            exportError = nil

            Task { @MainActor in
                do {
                    let url = try await exportService.exportAll(range: selectedRange)
                    exportedURL = url
                    showShareSheet = true
                    isExporting = false
                } catch {
                    exportError = error.localizedDescription
                    isExporting = false
                    debug(.default, "Data export failed: \(error)")
                }
            }
        }
    }
}
