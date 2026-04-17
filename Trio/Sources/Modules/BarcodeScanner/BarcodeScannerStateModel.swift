import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - StateModel

extension BarcodeScanner {
    final class StateModel: BaseStateModel<Provider> {
        // MARK: - Properties

        @Published var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(
            for: .video
        )
        @Published var isScanning = true
        @Published var isKeyboardVisible = false
        @Published var currentScannedItem: FoodItem?
        @Published private(set) var originalScannedNutriments: FoodItem.Nutriments?
        @Published var isFetchingProduct = false
        @Published var errorMessage: String?
        @Published var scannedProducts: [FoodItem] = []
        @Published var isEditingFromList: Bool = false
        @Published var isOpenFoodFactsLoggedIn = false
        @Published var isUploadingCorrection = false
        @Published var correctionUploadMessage: String?
        @Published var correctionUploadSucceeded = false

        @Published var scannedLabelBasisAmount: Double = 100.0

        // External control
        @Published var showListView = false
        var onAddTreatments: ((Decimal, Decimal, Decimal, String) -> Void)?
        var onDismiss: (() -> Void)?

        // Editor amount input
        @Published var editingAmount: Double = 0
        @Published var editingIsMl: Bool = false

        // Search State
        @Published var searchQuery = ""
        @Published var searchResults: [FoodItem] = []
        @Published var isSearching = false
        @Published var searchError: String?

        // MARK: - Private Properties

        private let client = OpenFoodFactsClient()
        private var lastScanTime: Date?
        private var lastScannedBarcode: String?
        private var lastScanWasSuccessful: Bool = false
        private let scanCooldownSeconds: TimeInterval = 1.0

        var hasOpenFoodFactsCredentialsConfigured: Bool {
            let username = settingsManager.settings.openFoodFactsUsername
            let password = settingsManager.settings.openFoodFactsPassword
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        }

        // MARK: - Lifecycle

        func handleAppear() {
            Task {
                await self.refreshOpenFoodFactsAuthStatus()
            }

            refreshCameraStatus()

            switch cameraStatus {
            case .notDetermined:
                requestCameraAccess()
            case .authorized:
                isScanning = true
            default:
                isScanning = false
                errorMessage = String(localized: "Camera access is required to scan barcodes.")
            }
        }

        // MARK: - Camera Access

        func refreshCameraStatus() {
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }

        private func requestCameraAccess() {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.refreshCameraStatus()
                    if granted {
                        self.errorMessage = nil
                        self.isScanning = true
                    } else {
                        self.isScanning = false
                        self.showTemporaryError(
                            String(
                                localized: "Camera permissions were denied. Enable them in Settings to continue."
                            )
                        )
                    }
                }
            }
        }

        func openAppSettings() {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }

        // MARK: - Barcode Scanning

        func reportScannerIssue(_ message: String) {
            showTemporaryError(message)
            isScanning = false
        }

        func scanAgain(resetResults: Bool = false) {
            guard cameraStatus == .authorized else { return }
            if resetResults {
                currentScannedItem = nil
                errorMessage = nil
                scannedProducts.removeAll()
                lastScanTime = nil
                lastScannedBarcode = nil
                lastScanWasSuccessful = false
            }
            isScanning = true
        }

        func didDetect(barcode: String) {
            Task { @MainActor in
                // Prevent rapid scanning - require cooldown between scans
                if let lastScan = lastScanTime, Date().timeIntervalSince(lastScan) < scanCooldownSeconds {
                    return
                }

                // Prevent rescanning the same barcode (valid or invalid)
                guard barcode != lastScannedBarcode else { return }

                lastScannedBarcode = barcode
                lastScanTime = Date()
                fetchProduct(for: barcode)
            }
        }

        private func fetchProduct(for barcode: String) {
            isFetchingProduct = true
            errorMessage = nil

            Task { @MainActor in
                do {
                    var fetchedProduct = try await client.fetchProduct(barcode: barcode)
                    self.setupEditingAmount(for: fetchedProduct)

                    // Pre-fill amount in the item for display, though editingAmount controls input
                    fetchedProduct.amount = self.editingAmount
                    fetchedProduct.isMlInput = self.editingIsMl

                    self.currentScannedItem = fetchedProduct
                    self.originalScannedNutriments = fetchedProduct.nutriments
                    self.correctionUploadMessage = nil
                    self.correctionUploadSucceeded = false
                    self.lastScanWasSuccessful = true
                    self.isFetchingProduct = false
                } catch {
                    guard !Task.isCancelled else { return }
                    self.currentScannedItem = nil
                    self.lastScanWasSuccessful = false
                    self.isFetchingProduct = false
                    self.showTemporaryError(
                        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                }
            }
        }

        /// Shows a transient error message that auto-clears after a short delay
        private func showTemporaryError(_ message: String, duration: TimeInterval = 3) {
            errorMessage = message
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration))
                // Only clear if no new error was set in the meantime
                if self.errorMessage == message {
                    self.errorMessage = nil
                }
            }
        }

        // MARK: - Product Management

        func removeScannedProduct(_ item: FoodItem) {
            scannedProducts.removeAll { $0.id == item.id }
        }

        func updateScannedProductAmount(_ item: FoodItem, amount: Double, isMlInput: Bool) {
            if let index = scannedProducts.firstIndex(where: { $0.id == item.id }) {
                scannedProducts[index].amount = amount
                scannedProducts[index].isMlInput = isMlInput
            }
        }

        func editScannedProduct(_ item: FoodItem) {
            // Set as current item for editing
            currentScannedItem = item
            originalScannedNutriments = item.nutriments
            correctionUploadMessage = nil
            correctionUploadSucceeded = false

            // Set up editing state
            editingAmount = item.amount
            editingIsMl = item.isMlInput

            // Stop scanning while editing
            isScanning = false
        }

        /// Updates a nutriment value for the currently displayed product
        func updateProductNutriment(
            keyPath: WritableKeyPath<FoodItem.Nutriments, Double?>,
            value: Double?
        ) {
            currentScannedItem?.nutriments[keyPath: keyPath] = value
            correctionUploadMessage = nil
            correctionUploadSucceeded = false
        }

        var hasNutrimentsDivergedFromOriginal: Bool {
            guard let current = currentScannedItem?.nutriments,
                  let original = originalScannedNutriments
            else {
                return false
            }

            return !areNutrimentsEqual(current, original)
        }

        var canUploadCorrectionToOpenFoodFacts: Bool {
            guard isOpenFoodFactsLoggedIn,
                  hasOpenFoodFactsCredentialsConfigured,
                  !isUploadingCorrection,
                  hasNutrimentsDivergedFromOriginal,
                  let barcode = currentScannedItem?.barcode?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !barcode.isEmpty
            else {
                return false
            }
            return true
        }

        func uploadNutritionCorrectionToOpenFoodFacts() {
            guard canUploadCorrectionToOpenFoodFacts,
                  let item = currentScannedItem,
                  let originalNutriments = originalScannedNutriments
            else { return }

            isUploadingCorrection = true
            correctionUploadMessage = nil
            correctionUploadSucceeded = false

            Task { @MainActor in
                defer { self.isUploadingCorrection = false }

                do {
                    try await client.uploadNutritionCorrection(for: item, comparedTo: originalNutriments)
                    self.originalScannedNutriments = item.nutriments
                    self.correctionUploadSucceeded = true
                    self.correctionUploadMessage = String(localized: "Uploaded to OpenFoodFactsDB.")
                    debug(
                        .service,
                        "OpenFoodFacts correction marked as uploaded in UI for code=\(item.barcode ?? "<nil>")"
                    )
                } catch {
                    self.correctionUploadSucceeded = false
                    self.correctionUploadMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    debug(
                        .service,
                        "OpenFoodFacts correction upload failed in UI flow for code=\(item.barcode ?? "<nil>"): \(error)"
                    )
                }
            }
        }

        /// Adds the currently displayed product (with edited nutriments) to the list
        func addProductToList() {
            guard var item = currentScannedItem else { return }

            // Update with latest user edits
            item.amount = editingAmount
            item.isMlInput = editingIsMl

            // If "Only Carbs" setting is on, ensure other macros are zeroed out
            if settingsManager.settings.barcodeScannerOnlyCarbs {
                item.nutriments.fatPer100g = 0
                item.nutriments.proteinPer100g = 0
            }

            if let index = scannedProducts.firstIndex(where: { $0.id == item.id }) {
                scannedProducts[index] = item
            } else {
                scannedProducts.append(item)
            }

            // Clear the editor and resume scanning
            clearScannedProduct()

            // Automatically switch to list view after adding
            showListView = true
        }

        /// Sets up editing state when a product is loaded
        func setupEditingAmount(for product: FoodItem) {
            // Determine initial amount and unit from serving info
            editingAmount = product.servingQuantity ?? 100
            if let servingUnit = product.servingQuantityUnit?.lowercased() {
                editingIsMl =
                    servingUnit.contains("ml") || servingUnit == "l" || servingUnit.contains("fl oz")
            } else {
                editingIsMl = product.defaultPortionIsMl
            }
        }

        func selectQuickPortion(amount: Double, unit: String) {
            if editingAmount == amount {
                // Deselect: revert to standard 100 basis
                editingAmount = 100
                currentScannedItem?.servingQuantity = nil
                currentScannedItem?.servingQuantityUnit = nil
            } else {
                editingAmount = amount
                currentScannedItem?.servingQuantity = amount
                currentScannedItem?.servingQuantityUnit = unit
            }
        }

        /// Clears the currently displayed product from the overlay
        func clearScannedProduct() {
            currentScannedItem = nil
            originalScannedNutriments = nil
            lastScannedBarcode = nil
            lastScanWasSuccessful = false
            errorMessage = nil
            correctionUploadMessage = nil
            correctionUploadSucceeded = false
            isScanning = true
        }

        /// Whether to show the editor view (product available)
        var showEditorView: Bool {
            currentScannedItem != nil
        }

        /// Cancels the current editing session and returns to scanner
        func cancelEditing() {
            // Clear all editing state (product was not added to list yet)
            currentScannedItem = nil
            originalScannedNutriments = nil
            lastScannedBarcode = nil
            lastScanWasSuccessful = false
            errorMessage = nil
            correctionUploadMessage = nil
            correctionUploadSucceeded = false
            editingAmount = 0
            editingIsMl = false
            isScanning = true
        }

        /// Performs the dismissal of the barcode scanner module
        func performDismissal() {
            if let onDismiss = onDismiss {
                onDismiss()
            } else {
                hideModal()
            }
        }

        /// Performs food search using Open Food Facts API
        func performFoodSearch() {
            searchError = nil
            searchResults = []

            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                isSearching = false
                return
            }

            isSearching = true

            Task { @MainActor in
                do {
                    searchResults = try await client.searchProducts(query: query)
                } catch {
                    searchError = error.localizedDescription
                    searchResults = []
                }
                isSearching = false
            }
        }

        private func areNutrimentsEqual(
            _ lhs: FoodItem.Nutriments,
            _ rhs: FoodItem.Nutriments,
            tolerance: Double = 0.0001
        ) -> Bool {
            guard lhs.basis == rhs.basis else { return false }

            func areEqual(_ a: Double?, _ b: Double?) -> Bool {
                switch (a, b) {
                case (nil, nil): return true
                case let (x?, y?): return abs(x - y) <= tolerance
                default: return false
                }
            }

            return areEqual(lhs.energyKcalPer100g, rhs.energyKcalPer100g)
                && areEqual(lhs.carbohydratesPer100g, rhs.carbohydratesPer100g)
                && areEqual(lhs.sugarsPer100g, rhs.sugarsPer100g)
                && areEqual(lhs.fatPer100g, rhs.fatPer100g)
                && areEqual(lhs.proteinPer100g, rhs.proteinPer100g)
                && areEqual(lhs.fiberPer100g, rhs.fiberPer100g)
        }

        private func refreshOpenFoodFactsAuthStatus() async {
            let username = settingsManager.settings.openFoodFactsUsername
            let password = settingsManager.settings.openFoodFactsPassword
            let hasCredentials = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty

            await client.setCredentials(username: username, password: password)

            guard hasCredentials else {
                await MainActor.run {
                    self.isOpenFoodFactsLoggedIn = false
                    self.isUploadingCorrection = false
                    self.correctionUploadMessage = nil
                    self.correctionUploadSucceeded = false
                }
                return
            }

            let alreadyAuthenticated = await client.hasValidSessionCookie()
            if alreadyAuthenticated {
                await MainActor.run { self.isOpenFoodFactsLoggedIn = true }
                return
            }

            let didLogin = (try? await client.login()) ?? false
            await MainActor.run {
                self.isOpenFoodFactsLoggedIn = didLogin
            }
        }
    }
}
