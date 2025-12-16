import AppIntents
import Foundation

/// App Intent used to open the Barcode AI scanner via Apple Shortcuts.
/// When invoked, this intent opens the app and navigates to the Barcode AI view
/// for scanning food barcodes and analyzing food images.
struct OpenBarcodeScannerIntent: AppIntent {
    /// Title of the action in the Shortcuts app.
    static var title = LocalizedStringResource("Open Barcode Scanner")

    /// Description of the action in the Shortcuts app.
    static var description = IntentDescription(.init("Opens Trio's Barcode scanner for scanning processed food"))

    /// This intent opens the app when run
    static var openAppWhenRun: Bool = true

    /// Performs the intent by opening the Barcode AI view.
    ///
    /// - Returns: An intent result indicating the action was triggered.
    @MainActor func perform() async throws -> some IntentResult {
        // Post notification to open BarcodeAI view
        Foundation.NotificationCenter.default.post(name: .openBarcodeAI, object: nil)
        return .result()
    }
}
