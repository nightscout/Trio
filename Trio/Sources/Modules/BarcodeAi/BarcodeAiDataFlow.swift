enum BarcodeAi {
    enum Config {
        static let geminiApiKeyKey = "BarcodeAi.geminiApiKey"
    }
}

protocol BarcodeAiProvider: Provider {}

protocol BarcodeScannerPreviewCoordinator: AnyObject {
    func capturePhoto()
}
