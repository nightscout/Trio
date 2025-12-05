import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

extension BarcodeAi {
    /// Represents a scanned product with user-entered amount.
    struct ScannedProductItem: Identifiable, Equatable {
        let id: UUID
        let product: OpenFoodFactsProduct
        var amount: Double
        var isMlInput: Bool
        var capturedImage: UIImage?

        init(product: OpenFoodFactsProduct, amount: Double = 0, isMlInput: Bool = false, capturedImage: UIImage? = nil) {
            id = UUID()
            self.product = product
            self.amount = amount
            self.isMlInput = isMlInput
            self.capturedImage = capturedImage
        }

        static func == (lhs: ScannedProductItem, rhs: ScannedProductItem) -> Bool {
            lhs.id == rhs.id &&
                lhs.product == rhs.product &&
                lhs.amount == rhs.amount &&
                lhs.isMlInput == rhs.isMlInput
            // Note: We don't compare capturedImage for Equatable
        }
    }

    @MainActor final class StateModel: BaseStateModel<Provider> {
        @Injected() private var keychain: Keychain!

        @Published var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        @Published var isScanning = false
        @Published var scannedBarcode: String?
        @Published var product: OpenFoodFactsProduct?
        @Published var isFetchingProduct = false
        @Published var errorMessage: String?
        @Published var scannedProducts: [ScannedProductItem] = []
        @Published var isAnalyzingImage = false
        @Published var shouldCapturePhoto = false
        @Published var lastCapturedImage: UIImage?

        private let client = OpenFoodFactsClient()
        private weak var cameraCoordinator: (BarcodeScannerPreviewCoordinator & AnyObject)?
        private var lastScanTime: Date?
        private let scanCooldownSeconds: TimeInterval = 1.0

        func setCameraCoordinator(_ coordinator: BarcodeScannerPreviewCoordinator) {
            print("[BarcodeAI] Camera coordinator set")
            cameraCoordinator = coordinator as? (BarcodeScannerPreviewCoordinator & AnyObject)
        }

        func handleAppear() {
            refreshCameraStatus()
            switch cameraStatus {
            case .notDetermined:
                requestCameraAccess()
            case .authorized:
                isScanning = true
            default:
                isScanning = false
                errorMessage = "Camera access is required to scan barcodes."
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
                        self.errorMessage = "Camera permissions were denied. Enable them in Settings to continue."
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
                lastCapturedImage = nil
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
            // Clear the last captured image so barcode products show their OpenFoodFacts image
            lastCapturedImage = nil

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

            showModal(for: .treatmentView(carbs: totalCarbs, fat: totalFat, protein: totalProtein, note: note))
        }

        func openAppSettings() {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }

        func capturePhoto() {
            print("[BarcodeAI] capturePhoto() called - cameraStatus: \(cameraStatus), isScanning: \(isScanning)")
            guard cameraStatus == .authorized else {
                print("[BarcodeAI] Camera not authorized: \(cameraStatus)")
                errorMessage = "Camera access is required to capture a photo."
                return
            }

            // Remember the current scanning state to restore after AI analysis
            let wasScanningBeforeCapture = isScanning

            // If camera session is not running, we need to start it briefly for the capture
            // The camera preview always runs, but we track scanning state separately
            if !isScanning {
                print("[BarcodeAI] Camera scanning is paused, will capture without restarting barcode scanning...")
            }

            // Capture the photo - camera preview is always running
            performCapture(restoreScanningState: wasScanningBeforeCapture)
        }

        private func performCapture(restoreScanningState _: Bool = true) {
            print("[BarcodeAI] performCapture() - calling coordinator.capturePhoto()...")
            if let coordinator = cameraCoordinator {
                print("[BarcodeAI] Coordinator found, calling capturePhoto()")
                coordinator.capturePhoto()
            } else {
                print("[BarcodeAI] ERROR: Coordinator not found")
                errorMessage = "Camera not ready. Please try again."
            }
        }

        func analyzeImageWithGemini(_ image: UIImage) {
            print("[BarcodeAI] analyzeImageWithGemini() called - image size: \(image.size)")
            isAnalyzingImage = true
            shouldCapturePhoto = false
            errorMessage = nil
            lastCapturedImage = image // Store the captured image for display

            Task {
                do {
                    print("[BarcodeAI] Getting API key from keychain...")
                    // Get API key from Keychain
                    guard let apiKey = keychain.getValue(String.self, forKey: Config.geminiApiKeyKey),
                          !apiKey.isEmpty
                    else {
                        print("[BarcodeAI] ERROR: API key not found or empty")
                        throw NSError(
                            domain: "BarcodeAI",
                            code: -1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Gemini API key not configured. Please set it in Settings > Services > AI."
                            ]
                        )
                    }
                    print("[BarcodeAI] API key found, length: \(apiKey.count)")

                    // Prepare image data - resize and compress to reduce tokens
                    print("[BarcodeAI] Resizing and compressing image...")
                    let resizedImage = image.resizedForAPI(maxDimension: 1024)
                    guard let imageData = resizedImage.jpegData(compressionQuality: 0.6) else {
                        print("[BarcodeAI] ERROR: Failed to convert image to JPEG")
                        throw NSError(
                            domain: "BarcodeAI",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to convert image"]
                        )
                    }
                    print(
                        "[BarcodeAI] Original size: \(image.size), Resized: \(resizedImage.size), Data size: \(imageData.count) bytes"
                    )

                    let base64Image = imageData.base64EncodedString()
                    print("[BarcodeAI] Base64 encoded, length: \(base64Image.count)")

                    // Prepare request
                    let prompt = """
                    You are a certified diabetologist and nutrition analyst trained in evidence-based portion estimation.
                    Your task is to analyze the provided food image and return a JSON-only response with precise, visually justified nutrition estimates.

                    Instructions:
                    • Base all estimates solely on the visible items in the image. Do not infer or assume foods, sauces, or ingredients that are not clearly identifiable.
                    • Use visible scale references (e.g., fork width ≈ 20 mm, plate diameter ≈ 26–28 cm, cup ≈ 240 ml, etc.) to estimate portion size.
                    • Estimate the total weight/volume of the visible food portion.
                    • Use "g" (grams) for solid foods and "ml" for liquids/beverages.
                    • If the type or quantity of a food is uncertain, lower confidence accordingly.
                    • Round values reasonably (e.g., to the nearest 1 g or 10 ml).
                    • The nutrition values (carbs_g, fat_g, protein_g) should be for the TOTAL estimated portion, not per 100g.
                    • Confidence should be a percentage (0-100) based on image clarity, food visibility, and estimation certainty.
                    • Return only valid JSON — no extra text, markdown, or commentary and do all of this in the English language.

                    JSON Output:
                    {
                      "description": "<short German description of visible foods>",
                      "estimated_amount": <number - total estimated weight in grams or volume in ml>,
                      "amount_unit": "<g or ml>",
                      "carbs_g": <number - total carbs for the estimated portion>,
                      "fat_g": <number - total fat for the estimated portion>,
                      "protein_g": <number - total protein for the estimated portion>,
                      "confidence_percent": <number 0-100 - how confident are you in this estimate>
                    }
                    """

                    // Build request body matching Google's API format (image first, then text)
                    let requestBody: [String: Any] = [
                        "contents": [[
                            "parts": [
                                [
                                    "inline_data": [
                                        "mime_type": "image/jpeg",
                                        "data": base64Image
                                    ]
                                ],
                                ["text": prompt]
                            ]
                        ]],
                        "generationConfig": [
                            "temperature": 0.4,
                            "topK": 32,
                            "topP": 1,
                            "maxOutputTokens": 4096
                        ]
                    ]

                    print("[BarcodeAI] Creating API request...")
                    // Use selected model from settings, or default to gemini-2.0-flash
                    let selectedModel = UserDefaults.standard.string(forKey: "geminiSelectedModel") ?? "gemini-2.0-flash"
                    let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(selectedModel):generateContent"
                    print("[BarcodeAI] API URL: \(urlString)")
                    print("[BarcodeAI] Using model: \(selectedModel)")
                    guard let url = URL(string: urlString) else {
                        print("[BarcodeAI] ERROR: Invalid API URL")
                        throw NSError(domain: "BarcodeAI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                    print("[BarcodeAI] Request headers: \(request.allHTTPHeaderFields ?? [:])")
                    print("[BarcodeAI] Request body size: \(request.httpBody?.count ?? 0) bytes")

                    print("[BarcodeAI] Sending request to Gemini API...")
                    let (data, response) = try await URLSession.shared.data(for: request)

                    print("[BarcodeAI] Response received. Status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")

                    // Debug: Print response headers and body for 404 errors
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                        print("[BarcodeAI] DEBUG 404 Response:")
                        print("[BarcodeAI] Headers: \(httpResponse.allHeaderFields)")
                        if let responseBody = String(data: data, encoding: .utf8) {
                            print("[BarcodeAI] Response body: \(responseBody)")
                        }
                    }

                    guard let httpResponse = response as? HTTPURLResponse,
                          200 ..< 300 ~= httpResponse.statusCode
                    else {
                        print(
                            "[BarcodeAI] ERROR: API request failed with status \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                        )
                        throw NSError(domain: "BarcodeAI", code: -4, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
                    }

                    // Parse response
                    print("[BarcodeAI] Parsing response...")
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let candidates = json["candidates"] as? [[String: Any]],
                          let firstCandidate = candidates.first,
                          let content = firstCandidate["content"] as? [String: Any],
                          let parts = content["parts"] as? [[String: Any]],
                          let firstPart = parts.first,
                          var text = firstPart["text"] as? String
                    else {
                        print("[BarcodeAI] ERROR: Failed to parse API response")
                        print("[BarcodeAI] Response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                        throw NSError(
                            domain: "BarcodeAI",
                            code: -5,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response"]
                        )
                    }

                    print("[BarcodeAI] Raw response text length: \(text.count)")

                    // Clean JSON from markdown if present
                    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.hasPrefix("```json") {
                        text = text.replacingOccurrences(of: "```json", with: "")
                        text = text.replacingOccurrences(of: "```", with: "")
                        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if text.hasPrefix("```") {
                        text = text.replacingOccurrences(of: "```", with: "")
                        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    print("[BarcodeAI] Cleaned JSON: \(text)")

                    // Parse nutrition data - can be single object or array of objects
                    guard let jsonData = text.data(using: .utf8),
                          let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? Any
                    else {
                        print("[BarcodeAI] ERROR: Failed to parse JSON")
                        print("[BarcodeAI] Raw JSON: \(text)")
                        throw NSError(
                            domain: "BarcodeAI",
                            code: -6,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response"]
                        )
                    }

                    // Convert to array of items (handle both single object and array)
                    let nutritionItems: [[String: Any]]
                    if let array = jsonObject as? [[String: Any]] {
                        nutritionItems = array
                        print("[BarcodeAI] Detected array with \(array.count) items")
                    } else if let single = jsonObject as? [String: Any] {
                        nutritionItems = [single]
                        print("[BarcodeAI] Detected single item")
                    } else {
                        print("[BarcodeAI] ERROR: Unexpected JSON format")
                        print("[BarcodeAI] Raw JSON: \(text)")
                        throw NSError(
                            domain: "BarcodeAI",
                            code: -6,
                            userInfo: [NSLocalizedDescriptionKey: "Unexpected JSON format"]
                        )
                    }

                    // Process each nutrition item
                    var addedProducts: [OpenFoodFactsProduct] = []

                    for (index, nutritionData) in nutritionItems.enumerated() {
                        guard let description = nutritionData["description"] as? String,
                              let carbs = nutritionData["carbs_g"] as? Double,
                              let fat = nutritionData["fat_g"] as? Double,
                              let protein = nutritionData["protein_g"] as? Double
                        else {
                            print("[BarcodeAI] WARNING: Skipping item \(index) - missing required fields")
                            continue
                        }

                        // Extract estimated amount and unit (with defaults)
                        let estimatedAmount = nutritionData["estimated_amount"] as? Double ?? 100.0
                        let amountUnit = nutritionData["amount_unit"] as? String ?? "g"
                        let isMl = amountUnit.lowercased() == "ml"

                        // Extract confidence percentage (default to 50 if not provided)
                        let confidencePercent = nutritionData["confidence_percent"] as? Double ?? 50.0

                        print(
                            "[BarcodeAI] Item \(index + 1): \(description) - carbs=\(carbs), fat=\(fat), protein=\(protein), amount=\(estimatedAmount)\(amountUnit), confidence=\(Int(confidencePercent))%"
                        )

                        // Calculate per-100g/ml values from total portion values
                        let factor = 100.0 / estimatedAmount
                        let carbsPer100 = carbs * factor
                        let fatPer100 = fat * factor
                        let proteinPer100 = protein * factor

                        // Create a product from AI analysis
                        let aiProduct = OpenFoodFactsProduct(
                            barcode: "AI-\(UUID().uuidString)",
                            name: "\(description)",
                            brand: "🤖 Gemini Vision • \(Int(confidencePercent))% confidence",
                            quantity: "\(Int(estimatedAmount))\(amountUnit) (estimated)",
                            servingSize: "\(Int(estimatedAmount))\(amountUnit)",
                            ingredients: nil,
                            imageURL: nil,
                            defaultPortionIsMl: isMl,
                            servingQuantity: estimatedAmount,
                            servingQuantityUnit: amountUnit,
                            nutriments: .init(
                                basis: isMl ? .per100ml : .per100g,
                                energyKcalPer100g: nil,
                                carbohydratesPer100g: carbsPer100,
                                sugarsPer100g: nil,
                                fatPer100g: fatPer100,
                                proteinPer100g: proteinPer100,
                                fiberPer100g: nil
                            )
                        )

                        let item = ScannedProductItem(
                            product: aiProduct,
                            amount: estimatedAmount,
                            isMlInput: isMl,
                            capturedImage: image
                        )

                        self.scannedProducts.append(item)
                        addedProducts.append(aiProduct)
                    }

                    if addedProducts.isEmpty {
                        throw NSError(
                            domain: "BarcodeAI",
                            code: -6,
                            userInfo: [NSLocalizedDescriptionKey: "No valid nutrition data found in response"]
                        )
                    }

                    // Set the first product as the current product
                    self.product = addedProducts.first
                    self.isAnalyzingImage = false
                    print("[BarcodeAI] Analysis complete! Added \(addedProducts.count) product(s)")

                } catch {
                    print("[BarcodeAI] ERROR in analyzeImageWithGemini: \(error)")
                    print("[BarcodeAI] Error details: \(error.localizedDescription)")
                    self.isAnalyzingImage = false
                    self.errorMessage = "AI Analysis failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

extension BarcodeAi {
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

extension BarcodeAi {
    enum OpenFoodFactsError: LocalizedError {
        case invalidResponse
        case productNotFound

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Unable to reach OpenFoodFacts. Please try again."
            case .productNotFound:
                return "No product information was found for this barcode."
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
                name: productData.productName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Unknown product",
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

private extension BarcodeAi.OpenFoodFactsClient {
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
        let basis: BarcodeAi.OpenFoodFactsProduct.Nutriments.Basis
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

private extension UIImage {
    /// Resizes the image to fit within a maximum dimension while maintaining aspect ratio.
    /// This reduces the number of tokens used when sending images to AI APIs.
    func resizedForAPI(maxDimension: CGFloat) -> UIImage {
        let currentMax = max(size.width, size.height)

        // If already smaller than maxDimension, return self
        guard currentMax > maxDimension else { return self }

        let scale = maxDimension / currentMax
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
