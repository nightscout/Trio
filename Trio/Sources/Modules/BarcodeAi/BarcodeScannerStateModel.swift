import AVFoundation
import Combine
import Foundation
import Observation
import SwiftUI

// MARK: - StateModel

extension BarcodeScanner {
    @Observable final class StateModel: BaseStateModel<Provider> {
        // MARK: - Properties

        var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        var isScanning = false
        var isKeyboardVisible = false
        var scannedBarcode: String?
        var product: OpenFoodFactsProduct?
        var isFetchingProduct = false
        var errorMessage: String?
        var scannedProducts: [ScannedProductItem] = []

        // Nutrition label scanning
        var capturedImage: UIImage?
        var scannedNutritionData: NutritionData?
        var isProcessingLabel = false
        var showNutritionEditor = false
        var editableNutritionName: String = ""

        // Editor amount input
        var editingAmount: Double = 0
        var editingIsMl: Bool = false

        // Camera frame for nutrition analysis
        var lastCameraFrame: UIImage?

        // AI Model for nutrition label extraction
        var modelManager: NutritionModelManager { NutritionModelManager.shared }

        /// Whether AI nutrition scanning is enabled (from settings)
        var isAINutritionScannerEnabled: Bool {
            guard resolver != nil else { return false }
            return settingsManager.settings.useAINutritionScanner
        }

        // MARK: - Private Properties

        private let client = OpenFoodFactsClient()
        private let nutritionScanner = NutritionLabelScanner()
        private var lastScanTime: Date?
        private let scanCooldownSeconds: TimeInterval = 1.0

        // MARK: - Lifecycle

        override func subscribe() {
            // No subscriptions needed for barcode scanner
        }

        func handleAppear() {
            refreshCameraStatus()
            modelManager.checkModelStatus()

            // Auto-load model if downloaded but not ready
            if case .downloaded = modelManager.state {
                Task {
                    try? await modelManager.loadModel()
                }
            }

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
                        self.errorMessage = String(
                            localized: "Camera permissions were denied. Enable them in Settings to continue."
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
            errorMessage = message
            isScanning = false
        }

        func scanAgain(resetResults: Bool = false) {
            guard cameraStatus == .authorized else { return }
            if resetResults {
                product = nil
                scannedBarcode = nil
                errorMessage = nil
                scannedProducts.removeAll()
                lastScanTime = nil
            }
            isScanning = true
        }

        func didDetect(barcode: String) {
            // Prevent rapid scanning - require cooldown between scans
            if let lastScan = lastScanTime, Date().timeIntervalSince(lastScan) < scanCooldownSeconds {
                return
            }

            guard barcode != scannedBarcode else { return }
            scannedBarcode = barcode
            lastScanTime = Date()
            fetchProduct(for: barcode)
        }

        private func fetchProduct(for barcode: String) {
            isFetchingProduct = true
            errorMessage = nil

            Task {
                do {
                    let fetchedProduct = try await client.fetchProduct(barcode: barcode)
                    self.product = fetchedProduct
                    self.setupEditingAmount(for: fetchedProduct)
                    self.isFetchingProduct = false
                    // Product is shown in editor for review/editing
                    // It will be added to list when user taps "Add to List"
                } catch {
                    guard !Task.isCancelled else { return }
                    self.product = nil
                    self.isFetchingProduct = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }

        // MARK: - Product Management

        func removeScannedProduct(_ item: ScannedProductItem) {
            scannedProducts.removeAll { $0.id == item.id }
            // Allow re-scanning if no other product with the same barcode exists
            if !scannedProducts.contains(where: { $0.product.barcode == item.product.barcode }) {
                if scannedBarcode == item.product.barcode {
                    scannedBarcode = nil
                }
            }
        }

        func updateScannedProductAmount(_ item: ScannedProductItem, amount: Double, isMlInput: Bool) {
            if let index = scannedProducts.firstIndex(where: { $0.id == item.id }) {
                scannedProducts[index].amount = amount
                scannedProducts[index].isMlInput = isMlInput
            }
        }

        /// Updates a nutriment value for the currently displayed product
        func updateProductNutriment(
            keyPath: WritableKeyPath<OpenFoodFactsProduct.Nutriments, Double?>,
            value: Double?
        ) {
            product?.nutriments[keyPath: keyPath] = value
        }

        /// Adds the currently displayed product (with edited nutriments) to the list
        func addProductToList() {
            guard let currentProduct = product else { return }

            // Add the edited product to the list with user-specified amount
            let item = ScannedProductItem(
                product: currentProduct,
                amount: editingAmount,
                isMlInput: editingIsMl
            )
            scannedProducts.append(item)

            // Clear the editor and resume scanning
            clearScannedProduct()
        }

        /// Sets up editing state when a product is loaded
        func setupEditingAmount(for product: OpenFoodFactsProduct) {
            // Determine initial amount and unit from serving info
            editingAmount = product.servingQuantity ?? 100
            if let servingUnit = product.servingQuantityUnit?.lowercased() {
                editingIsMl = servingUnit.contains("ml") || servingUnit == "l" || servingUnit.contains("fl oz")
            } else {
                editingIsMl = product.defaultPortionIsMl
            }
        }

        /// Clears the currently displayed product from the overlay
        func clearScannedProduct() {
            product = nil
            scannedBarcode = nil
            errorMessage = nil
            isScanning = true
        }

        /// Clears the scanned nutrition data from the overlay
        func clearScannedNutrition() {
            scannedNutritionData = nil
            capturedImage = nil
            errorMessage = nil
            isScanning = true
        }

        /// Cancels the current editing session and returns to scanner
        func cancelEditing() {
            // Clear all editing state (product was not added to list yet)
            product = nil
            scannedBarcode = nil
            scannedNutritionData = nil
            capturedImage = nil
            errorMessage = nil
            editingAmount = 0
            editingIsMl = false
            isScanning = true
        }

        /// Opens the Treatments view with carbs, fat and protein prefilled
        func openInTreatments() {
            var totalCarbs: Decimal = 0
            var totalFat: Decimal = 0
            var totalProtein: Decimal = 0
            var productNames: [String] = []

            for item in scannedProducts where item.amount > 0 {
                let amountDecimal = Decimal(item.amount)

                func macro(_ per100g: Double?) -> Decimal {
                    guard let per100g else { return 0 }
                    return amountDecimal * Decimal(per100g) / 100
                }

                totalCarbs += macro(item.product.nutriments.carbohydratesPer100g)
                totalFat += macro(item.product.nutriments.fatPer100g)
                totalProtein += macro(item.product.nutriments.proteinPer100g)

                productNames.append(item.product.name)
            }

            let note = productNames.joined(separator: ", ")
            showModal(for: .barcodeScannerTreatment(carbs: totalCarbs, fat: totalFat, protein: totalProtein, note: note))
        }

        // MARK: - Nutrition Label Scanning

        /// Captures the current camera frame for nutrition label analysis
        func captureFrameForNutritionAnalysis() {
            guard let frame = lastCameraFrame else {
                errorMessage = String(localized: "No camera frame available. Please try again.")
                return
            }

            isScanning = false
            didCapturePhoto(frame)
        }

        /// Called when a photo is captured from the camera
        func didCapturePhoto(_ image: UIImage) {
            capturedImage = image
            isScanning = false
            processNutritionLabel(image)
        }

        /// Processes a captured image to extract nutrition data
        private func processNutritionLabel(_ image: UIImage) {
            isProcessingLabel = true
            errorMessage = nil

            Task {
                do {
                    let data: NutritionData

                    // Use AI model if available and enabled, otherwise fall back to regex-based OCR
                    if isAINutritionScannerEnabled, modelManager.isReady {
                        data = try await nutritionScanner.scanWithAIModel(from: image, modelManager: modelManager)
                    } else {
                        data = try await nutritionScanner.scanNutritionLabel(from: image)
                    }

                    await MainActor.run {
                        self.scannedNutritionData = data
                        self.isProcessingLabel = false

                        if data.hasAnyData {
                            self.showNutritionEditor = true
                            self.editableNutritionName = String(localized: "Scanned Label")
                        } else {
                            self.errorMessage = String(localized: "No nutrition information found. Try taking a clearer photo.")
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.isProcessingLabel = false
                        self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
        }

        // MARK: - Model Management

        /// Loads the AI model if downloaded
        func loadModelIfNeeded() {
            guard modelManager.state == .downloaded else { return }
            Task {
                try? await modelManager.loadModel()
            }
        }

        /// Deletes the downloaded model
        func deleteModel() {
            modelManager.deleteModel()
        }

        /// Clears the captured image and returns to live camera
        func clearCapturedImage() {
            capturedImage = nil
            scannedNutritionData = nil
            showNutritionEditor = false
            errorMessage = nil
            isScanning = true
        }

        /// Adds the scanned nutrition data as a product item
        func addScannedNutritionLabel() {
            guard let data = scannedNutritionData else { return }

            let product = data.toProduct(
                name: editableNutritionName.isEmpty ? String(localized: "Scanned Label") : editableNutritionName
            )
            let item = ScannedProductItem(
                product: product,
                amount: data.servingSizeGrams ?? 100,
                isMlInput: false,
                isManualEntry: true
            )

            scannedProducts.append(item)

            // Reset for next scan
            capturedImage = nil
            scannedNutritionData = nil
            showNutritionEditor = false
            editableNutritionName = ""
            isScanning = true
        }

        /// Adds the scanned nutrition data directly to meals (inline editing)
        func addScannedNutritionToMeals() {
            guard let data = scannedNutritionData else { return }

            let product = data.toProduct(name: String(localized: "Scanned Label"))
            let item = ScannedProductItem(
                product: product,
                amount: data.servingSizeGrams ?? 100,
                isMlInput: false,
                isManualEntry: true
            )

            scannedProducts.append(item)

            // Reset for next scan
            capturedImage = nil
            scannedNutritionData = nil
            errorMessage = nil
            isScanning = true
        }

        /// Updates the scanned nutrition data with edited values
        func updateScannedNutritionData(
            calories: Double?,
            carbohydrates: Double?,
            sugars: Double?,
            fat: Double?,
            protein: Double?,
            fiber: Double?,
            servingSizeGrams: Double?
        ) {
            scannedNutritionData = NutritionData(
                calories: calories,
                carbohydrates: carbohydrates,
                sugars: sugars,
                fat: fat,
                saturatedFat: scannedNutritionData?.saturatedFat,
                protein: protein,
                fiber: fiber,
                sodium: scannedNutritionData?.sodium,
                servingSize: scannedNutritionData?.servingSize,
                servingSizeGrams: servingSizeGrams
            )
        }
    }
}
