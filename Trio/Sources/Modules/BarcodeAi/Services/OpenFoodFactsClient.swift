import Foundation

// MARK: - OpenFoodFacts API Client

extension BarcodeScanner {
    /// Client for fetching product data from OpenFoodFacts API
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

            // Decide preferred portion unit for user input
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

// MARK: - Errors

extension BarcodeScanner {
    enum OpenFoodFactsError: LocalizedError {
        case invalidResponse
        case productNotFound

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                String(localized: "Unable to reach OpenFoodFacts. Please try again.")
            case .productNotFound:
                String(localized: "No product information was found for this barcode.")
            }
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

            // Decide if data is per 100g or per 100ml based on available keys
            let hasPer100g = raw.keys.contains { $0.hasSuffix("_100g") }
            let hasPer100ml = raw.keys.contains { $0.hasSuffix("_100ml") }

            if hasPer100ml, !hasPer100g {
                basis = .per100ml
            } else {
                basis = .per100g
            }
        }

        /// Helper type that can decode either a number or a string and expose it as Double
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

                doubleValue = nil
            }
        }
    }
}

// MARK: - String Extension

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
