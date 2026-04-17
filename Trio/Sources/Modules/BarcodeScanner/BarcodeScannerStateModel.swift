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
        @Published var isFetchingProduct = false
        @Published var errorMessage: String?
        @Published var scannedProducts: [FoodItem] = []
        @Published var isEditingFromList: Bool = false

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

        // MARK: - Lifecycle

        func handleAppear() {
            Task {
                await client.setCredentials(
                    username: settingsManager.settings.openFoodFactsUsername,
                    password: settingsManager.settings.openFoodFactsPassword
                )
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
            lastScannedBarcode = nil
            lastScanWasSuccessful = false
            errorMessage = nil
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
            lastScannedBarcode = nil
            lastScanWasSuccessful = false
            errorMessage = nil
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
    }
}
