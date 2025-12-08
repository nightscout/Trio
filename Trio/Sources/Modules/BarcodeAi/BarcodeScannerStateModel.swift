import AVFoundation
import Combine
import Foundation
import Observation
import SwiftUI

extension BarcodeScanner {
    /// Scan mode for the barcode scanner
    enum ScanMode: String, CaseIterable {
        case barcode = "Barcode"
        case nutritionLabel = "Nutrition Label"

        var icon: String {
            switch self {
            case .barcode: return "barcode.viewfinder"
            case .nutritionLabel: return "doc.text.viewfinder"
            }
        }

        var localizedName: String {
            switch self {
            case .barcode: return String(localized: "Barcode")
            case .nutritionLabel: return String(localized: "Nutrition Label")
            }
        }
    }

    /// Represents a scanned product with user-entered amount.
    struct ScannedProductItem: Identifiable, Equatable {
        let id: UUID
        let product: OpenFoodFactsProduct
        var amount: Double
        var isMlInput: Bool
        let isManualEntry: Bool

        init(product: OpenFoodFactsProduct, amount: Double = 0, isMlInput: Bool = false, isManualEntry: Bool = false) {
            id = UUID()
            self.product = product
            self.amount = amount
            self.isMlInput = isMlInput
            self.isManualEntry = isManualEntry
        }

        static func == (lhs: ScannedProductItem, rhs: ScannedProductItem) -> Bool {
            lhs.id == rhs.id &&
                lhs.product == rhs.product &&
                lhs.amount == rhs.amount &&
                lhs.isMlInput == rhs.isMlInput &&
                lhs.isManualEntry == rhs.isManualEntry
        }
    }

    @Observable final class StateModel: BaseStateModel<Provider> {
        var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        var isScanning = false
        var scannedBarcode: String?
        var product: OpenFoodFactsProduct?
        var isFetchingProduct = false
        var errorMessage: String?
        var scannedProducts: [ScannedProductItem] = []

        // Scan mode
        var scanMode: ScanMode = .barcode

        // Nutrition label scanning
        var isCapturingPhoto = false
        var capturedImage: UIImage?
        var scannedNutritionData: NutritionLabelScanner.NutritionData?
        var isProcessingLabel = false
        var showNutritionEditor = false
        var editableNutritionName: String = ""
        var showCameraPicker = false

        // AI Model for nutrition label extraction
        let modelManager = NutritionModelManager()
        var showModelFilePicker = false
        var useAIModel = true // Toggle between AI model and regex-based extraction

        private let client = OpenFoodFactsClient()
        private let nutritionScanner = NutritionLabelScanner()
        private var lastScanTime: Date?
        private let scanCooldownSeconds: TimeInterval = 1.0

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
                        self
                            .errorMessage =
                            String(localized: "Camera permissions were denied. Enable them in Settings to continue.")
                    }
                }
            }
        }

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
            // Prevent rapid scanning - require 1 second cooldown between scans
            if let lastScan = lastScanTime, Date().timeIntervalSince(lastScan) < scanCooldownSeconds {
                return
            }

            guard barcode != scannedBarcode else { return }
            scannedBarcode = barcode
            lastScanTime = Date()
            // Keep scanning running - don't pause after detecting a barcode
            fetchProduct(for: barcode)
        }

        private func fetchProduct(for barcode: String) {
            isFetchingProduct = true
            errorMessage = nil

            Task {
                do {
                    let fetchedProduct = try await client.fetchProduct(barcode: barcode)
                    self.product = fetchedProduct
                    self.isFetchingProduct = false
                    // Add to scanned products list with serving quantity if available
                    let initialAmount = fetchedProduct.servingQuantity ?? 0
                    let initialIsMl: Bool
                    if let servingUnit = fetchedProduct.servingQuantityUnit?.lowercased() {
                        initialIsMl = servingUnit.contains("ml") || servingUnit == "l" || servingUnit.contains("fl oz")
                    } else {
                        initialIsMl = fetchedProduct.defaultPortionIsMl
                    }

                    let item = ScannedProductItem(
                        product: fetchedProduct,
                        amount: initialAmount,
                        isMlInput: initialIsMl
                    )
                    self.scannedProducts.append(item)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.product = nil
                    self.isFetchingProduct = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }

        func removeScannedProduct(_ item: ScannedProductItem) {
            scannedProducts.removeAll { $0.id == item.id }
            // Reset scannedBarcode if we removed the last product with that barcode
            // This allows the same barcode to be scanned again
            if !scannedProducts.contains(where: { $0.product.barcode == item.product.barcode }) {
                // If no other product with the same barcode exists, allow re-scanning
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

        /// Opens the Treatments view with carbs, fat and protein prefilled
        /// based on all scanned products with amounts.
        func openInTreatments() {
            var totalCarbs: Decimal = 0
            var totalFat: Decimal = 0
            var totalProtein: Decimal = 0
            var productNames: [String] = []

            for item in scannedProducts where item.amount > 0 {
                // Convert the entered amount into the basis used by nutriments.
                // We currently approximate 1 g ≈ 1 ml if they don't match.
                let amountInBasisUnits: Double
                switch item.product.nutriments.basis {
                case .per100g:
                    amountInBasisUnits = item.amount // ml treated ~ g
                case .per100ml:
                    amountInBasisUnits = item.amount // g treated ~ ml
                }

                let amountDecimal = Decimal(amountInBasisUnits)

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

        func openAppSettings() {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }

        // MARK: - Nutrition Label Scanning

        /// Switches the scan mode
        func switchScanMode(to mode: ScanMode) {
            scanMode = mode
            errorMessage = nil

            // Reset nutrition label specific state when switching away
            if mode == .barcode {
                capturedImage = nil
                scannedNutritionData = nil
                showNutritionEditor = false
                editableNutritionName = ""
            }
        }

        /// Captures a photo for nutrition label scanning
        func capturePhoto() {
            print("📸 [StateModel] capturePhoto() triggered, setting isCapturingPhoto = true")
            isCapturingPhoto = true
        }

        /// Called when a photo is captured from the camera
        func didCapturePhoto(_ image: UIImage) {
            print("📷 [StateModel] Photo captured!")
            print("📷 [StateModel] Image dimensions: \(image.size.width) x \(image.size.height)")
            isCapturingPhoto = false
            capturedImage = image
            isScanning = false
            processNutritionLabel(image)
        }

        /// Processes a captured image to extract nutrition data
        private func processNutritionLabel(_ image: UIImage) {
            print("📸 [StateModel] Processing nutrition label...")
            print("📸 [StateModel] Image size: \(image.size)")
            print("📸 [StateModel] useAIModel: \(useAIModel), modelReady: \(modelManager.isReady)")

            isProcessingLabel = true
            errorMessage = nil

            Task {
                do {
                    let data: NutritionLabelScanner.NutritionData

                    // Use AI model if available and enabled, otherwise fall back to regex-based OCR
                    if useAIModel, modelManager.isReady {
                        print("🤖 [StateModel] Using AI model for extraction...")
                        data = try await nutritionScanner.scanWithAIModel(from: image, modelManager: modelManager)
                    } else {
                        print("📝 [StateModel] Using regex-based extraction...")
                        // Fall back to regex-based OCR extraction
                        data = try await nutritionScanner.scanNutritionLabel(from: image)
                    }

                    print("✅ [StateModel] Extraction complete - hasData: \(data.hasAnyData)")
                    print(
                        "✅ [StateModel] Calories: \(String(describing: data.calories)), Carbs: \(String(describing: data.carbohydrates))"
                    )

                    await MainActor.run {
                        self.scannedNutritionData = data
                        self.isProcessingLabel = false

                        if data.hasAnyData {
                            print("✅ [StateModel] Showing nutrition editor")
                            self.showNutritionEditor = true
                            self.editableNutritionName = String(localized: "Scanned Label")
                        } else {
                            print("⚠️ [StateModel] No nutrition data found")
                            self.errorMessage = String(localized: "No nutrition information found. Try taking a clearer photo.")
                        }
                    }
                } catch {
                    print("❌ [StateModel] Extraction failed: \(error)")
                    print("❌ [StateModel] Error: \(error.localizedDescription)")
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

        /// Retakes the nutrition label photo
        func retakePhoto() {
            capturedImage = nil
            scannedNutritionData = nil
            showNutritionEditor = false
            errorMessage = nil
            isScanning = true
        }

        /// Adds the scanned nutrition data as a product item
        func addScannedNutritionLabel() {
            guard let data = scannedNutritionData else { return }

            let product = data
                .toProduct(name: editableNutritionName.isEmpty ? String(localized: "Scanned Label") : editableNutritionName)
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
            scannedNutritionData = NutritionLabelScanner.NutritionData(
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

// MARK: - OpenFoodFacts Models

extension BarcodeScanner {
    struct OpenFoodFactsProduct: Identifiable, Equatable {
        struct Nutriments: Equatable {
            enum Basis: Equatable {
                case per100g
                case per100ml
            }

            let basis: Basis
            let energyKcalPer100g: Double?
            let carbohydratesPer100g: Double?
            let sugarsPer100g: Double?
            let fatPer100g: Double?
            let proteinPer100g: Double?
            let fiberPer100g: Double?
        }

        var id: String { barcode }

        let barcode: String
        let name: String
        let brand: String?
        let quantity: String?
        let servingSize: String?
        let ingredients: String?
        let imageURL: URL?
        /// Preferred unit for user input (true = ml, false = g),
        /// primarily derived from `product_quantity_unit`.
        let defaultPortionIsMl: Bool
        let servingQuantity: Double?
        let servingQuantityUnit: String?
        let nutriments: Nutriments
    }
}

// MARK: - OpenFoodFacts Client

extension BarcodeScanner {
    enum OpenFoodFactsError: LocalizedError {
        case invalidResponse
        case productNotFound

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return String(localized: "Unable to reach OpenFoodFacts. Please try again.")
            case .productNotFound:
                return String(localized: "No product information was found for this barcode.")
            }
        }
    }

    struct OpenFoodFactsClient {
        func fetchProduct(barcode: String) async throws -> OpenFoodFactsProduct {
            guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
                throw OpenFoodFactsError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode
            else {
                throw OpenFoodFactsError.invalidResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let apiResponse = try decoder.decode(APIResponse.self, from: data)

            guard apiResponse.status == 1, let productData = apiResponse.product else {
                throw OpenFoodFactsError.productNotFound
            }

            // Decide preferred portion unit for user input:
            // 1) Use `serving_quantity_unit` if available
            // 2) Use `product_quantity_unit` if available (ml/l → ml, sonst g)
            // 3) Fallback: if nutriments are per 100ml, default to ml, sonst g.
            let servingUnit = productData.servingQuantityUnit?.lowercased() ?? productData.productQuantityUnit?.lowercased()
            let isMlQuantityUnit: Bool = {
                if let unit = servingUnit {
                    if unit.contains("ml") || unit == "l" || unit.contains("fl oz") {
                        return true
                    }
                    return false
                }
                return productData.nutriments?.basis == .per100ml
            }()

            return OpenFoodFactsProduct(
                barcode: apiResponse.code,
                name: productData.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmpty ?? String(localized: "Unknown product"),
                brand: productData.primaryBrand,
                quantity: productData.quantity,
                servingSize: productData.servingSize,
                ingredients: productData.ingredientsText,
                imageURL: productData.imageURL,
                defaultPortionIsMl: isMlQuantityUnit,
                servingQuantity: productData.servingQuantity,
                servingQuantityUnit: productData.servingQuantityUnit,
                nutriments: .init(
                    basis: productData.nutriments?.basis ?? .per100g,
                    energyKcalPer100g: productData.nutriments?.energyKcal100g,
                    carbohydratesPer100g: productData.nutriments?.carbohydrates100g,
                    sugarsPer100g: productData.nutriments?.sugars100g,
                    fatPer100g: productData.nutriments?.fat100g,
                    proteinPer100g: productData.nutriments?.proteins100g,
                    fiberPer100g: productData.nutriments?.fiber100g
                )
            )
        }
    }
}

// MARK: - Private API Response Types

private extension BarcodeScanner.OpenFoodFactsClient {
    struct APIResponse: Decodable {
        let status: Int
        let statusVerbose: String
        let code: String
        let product: ProductData?
    }

    struct ProductData: Decodable {
        let productName: String?
        let brands: String?
        let quantity: String?
        let productQuantityUnit: String?
        let servingSize: String?
        let servingQuantity: Double?
        let servingQuantityUnit: String?
        let ingredientsText: String?
        let imageUrl: String?
        let imageFrontUrl: String?
        let imageFrontThumbUrl: String?
        let nutriments: NutrimentsData?

        private enum CodingKeys: String, CodingKey {
            case productName
            case brands
            case quantity
            case productQuantityUnit
            case servingSize
            case servingQuantity
            case servingQuantityUnit
            case ingredientsText
            case imageUrl
            case imageFrontUrl
            case imageFrontThumbUrl
            case nutriments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            productName = try container.decodeIfPresent(String.self, forKey: .productName)
            brands = try container.decodeIfPresent(String.self, forKey: .brands)
            quantity = try container.decodeIfPresent(String.self, forKey: .quantity)
            productQuantityUnit = try container.decodeIfPresent(String.self, forKey: .productQuantityUnit)
            servingSize = try container.decodeIfPresent(String.self, forKey: .servingSize)
            servingQuantityUnit = try container.decodeIfPresent(String.self, forKey: .servingQuantityUnit)
            ingredientsText = try container.decodeIfPresent(String.self, forKey: .ingredientsText)
            imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
            imageFrontUrl = try container.decodeIfPresent(String.self, forKey: .imageFrontUrl)
            imageFrontThumbUrl = try container.decodeIfPresent(String.self, forKey: .imageFrontThumbUrl)
            nutriments = try container.decodeIfPresent(NutrimentsData.self, forKey: .nutriments)

            // servingQuantity can be either a Double or a String in the API response
            if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: .servingQuantity) {
                servingQuantity = doubleValue
            } else if let stringValue = try? container.decodeIfPresent(String.self, forKey: .servingQuantity),
                      let parsed = Double(stringValue.replacingOccurrences(of: ",", with: "."))
            {
                servingQuantity = parsed
            } else {
                servingQuantity = nil
            }
        }

        var primaryBrand: String? {
            brands?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first
        }

        var imageURL: URL? {
            [imageFrontUrl, imageFrontThumbUrl, imageUrl]
                .compactMap { $0 }
                .compactMap { URL(string: $0) }
                .first
        }
    }

    struct NutrimentsData: Decodable {
        let basis: BarcodeScanner.OpenFoodFactsProduct.Nutriments.Basis
        let energyKcal100g: Double?
        let carbohydrates100g: Double?
        let sugars100g: Double?
        let fat100g: Double?
        let proteins100g: Double?
        let fiber100g: Double?

        init(from decoder: Decoder) throws {
            // OFF nutriments is a flat dictionary [String: Any], with values sometimes
            // encoded as numbers and sometimes as strings. We decode it as
            // [String: NumericValue] and then extract what we need.
            let container = try decoder.singleValueContainer()
            let raw = try container.decode([String: NumericValue].self)

            func value(_ key: String, fallbacks: [String] = []) -> Double? {
                if let v = raw[key]?.doubleValue {
                    return v
                }
                for fb in fallbacks {
                    if let v = raw[fb]?.doubleValue {
                        return v
                    }
                }
                return nil
            }

            energyKcal100g = value(
                "energy-kcal_100g",
                fallbacks: ["energy-kcal_100ml", "energy-kcal_serving"]
            )
            carbohydrates100g = value(
                "carbohydrates_100g",
                fallbacks: ["carbohydrates_100ml", "carbohydrates_serving"]
            )
            sugars100g = value(
                "sugars_100g",
                fallbacks: ["sugars_100ml", "sugars_serving"]
            )
            fat100g = value(
                "fat_100g",
                fallbacks: ["fat_100ml", "fat_serving"]
            )
            proteins100g = value(
                "proteins_100g",
                fallbacks: ["proteins_100ml", "proteins_serving"]
            )
            fiber100g = value(
                "fiber_100g",
                fallbacks: ["fiber_100ml", "fiber_serving"]
            )

            // Decide if data is per 100g or per 100ml based on available keys.
            let hasPer100g = raw.keys.contains { $0.hasSuffix("_100g") }
            let hasPer100ml = raw.keys.contains { $0.hasSuffix("_100ml") }

            if hasPer100ml, !hasPer100g {
                basis = .per100ml
            } else {
                basis = .per100g
            }
        }

        /// Helper type that can decode either a number or a string and expose it as Double.
        private struct NumericValue: Decodable {
            let doubleValue: Double?

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()

                if let d = try? container.decode(Double.self) {
                    doubleValue = d
                    return
                }

                if let s = try? container.decode(String.self) {
                    doubleValue = Double(s.replacingOccurrences(of: ",", with: "."))
                    return
                }

                // Any other type we treat as missing
                doubleValue = nil
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
