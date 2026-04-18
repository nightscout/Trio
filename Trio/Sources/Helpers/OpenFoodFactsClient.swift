import Foundation

// MARK: - OpenFoodFacts API Client

extension BarcodeScanner {
    /// Client for fetching product data from OpenFoodFacts API
    struct OpenFoodFactsClient {
        private static let authStore = OpenFoodFactsAuthStore()

        func setCredentials(username: String, password: String) async {
            await Self.authStore.setCredentials(username: username, password: password)
        }

        func hasValidSessionCookie() async -> Bool {
            await Self.authStore.hasValidSessionCookie()
        }

        @discardableResult func login() async throws -> Bool {
            guard let credentials = await Self.authStore.credentialsIfAvailable else {
                return false
            }

            let loginURL = URL(string: "https://world.openfoodfacts.org/cgi/session.pl")!
            var request = URLRequest(url: loginURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request
                .httpBody =
                "user_id=\(credentials.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? credentials.username)&password=\(credentials.password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? credentials.password)"
                    .data(using: .utf8)

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode
            else {
                return false
            }

            let responseHeaders = Dictionary(uniqueKeysWithValues: httpResponse.allHeaderFields.map {
                (String(describing: $0.key), String(describing: $0.value))
            })

            let cookies = HTTPCookie.cookies(withResponseHeaderFields: responseHeaders, for: loginURL)
            if let sessionCookie = cookies.first(where: { $0.name.localizedCaseInsensitiveContains("session") })
                ?? cookies.first
            {
                HTTPCookieStorage.shared.setCookie(sessionCookie)
                await Self.authStore.storeSessionCookie(sessionCookie)
                return true
            }

            if let storedCookie = HTTPCookieStorage.shared.cookies?.first(where: {
                $0.domain.contains("openfoodfacts.org") && $0.name.localizedCaseInsensitiveContains("session")
            }) {
                await Self.authStore.storeSessionCookie(storedCookie)
                return true
            }

            return false
        }

        func fetchProduct(barcode: String) async throws -> FoodItem {
            guard
                let url =
                URL(
                    string:
                    "https://world.openfoodfacts.org/api/v2/product/\(barcode).json&fields=code,product_name,image_url,image_front_small_url,nutriments,serving_quantity_unit,serving_quantity,product_quantity,product_quantity_unit"
                )
            else {
                throw OpenFoodFactsError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request = try await applySessionCookie(to: request)

            let (data, response) = try await performRequestWithReauthentication(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenFoodFactsError.invalidResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            // Try to decode the response even for 404s, as the API returns useful JSON
            let apiResponse = try decoder.decode(APIResponse.self, from: data)

            // Check if product was found based on status field in JSON
            guard apiResponse.status == 1, let productData = apiResponse.product else {
                throw OpenFoodFactsError.productNotFound
            }

            // For other HTTP errors (5xx, etc.), throw invalidResponse
            guard 200 ..< 500 ~= httpResponse.statusCode else {
                throw OpenFoodFactsError.invalidResponse
            }

            // Decide preferred portion unit for user input
            let servingUnit =
                productData.servingQuantityUnit?.lowercased()
                    ?? productData.productQuantityUnit?.lowercased()
            let servingSize = productData.servingQuantity ?? productData.productQuantity
            let isMlQuantityUnit: Bool = {
                if let unit = servingUnit {
                    if unit.contains("ml") || unit.contains("l") || unit.contains("fl oz") {
                        return true
                    }
                    return false
                }
                return productData.nutriments?.basis == .per100ml
            }()

            var imageSource: FoodItem.ImageSource = .none
            if let url = productData.imageURL {
                imageSource = .url(url)
            }

            return FoodItem(
                barcode: apiResponse.code,
                name: productData.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmpty ?? String(localized: "Unknown product"),
                brand: productData.primaryBrand,
                quantity: productData.quantity,
                servingSize: productData.servingSize,
                ingredients: productData.ingredientsText,
                imageSource: imageSource,
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

        /// Search products by name/text query
        /// - Parameters:
        ///   - query: The search term to look for
        ///   - page: Page number for pagination (1-indexed)
        ///   - pageSize: Number of results per page
        /// - Returns: Array of matching FoodItems
        func searchProducts(query: String, page: Int = 1, pageSize: Int = 24) async throws -> [FoodItem]
        {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }

            guard var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
            else {
                throw OpenFoodFactsError.invalidResponse
            }

            components.queryItems = [
                URLQueryItem(name: "search_terms", value: query),
                URLQueryItem(name: "search_simple", value: "1"),
                URLQueryItem(name: "action", value: "process"),
                URLQueryItem(name: "json", value: "1"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize))
            ]

            guard let url = components.url else {
                throw OpenFoodFactsError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Trio-iOS/1.0", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData // No cache
            request = try await applySessionCookie(to: request)

            let (data, response) = try await performRequestWithReauthentication(request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode
            else {
                throw OpenFoodFactsError.invalidResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let searchResponse = try decoder.decode(SearchAPIResponse.self, from: data)

            return searchResponse.products.compactMap { productData -> FoodItem? in
                let servingUnit =
                    productData.servingQuantityUnit?.lowercased()
                        ?? productData.productQuantityUnit?
                        .lowercased()
                let isMlQuantityUnit: Bool = {
                    if let unit = servingUnit {
                        if unit.contains("ml") || unit.contains("l") || unit.contains("fl oz") {
                            return true
                        }
                        return false
                    }
                    return productData.nutriments?.basis == .per100ml
                }()

                var imageSource: FoodItem.ImageSource = .none
                if let url = productData.imageURL {
                    imageSource = .url(url)
                }

                return FoodItem(
                    barcode: productData.code,
                    name: productData.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
                        .nonEmpty ?? String(localized: "Unknown product"),
                    brand: productData.primaryBrand,
                    quantity: productData.quantity,
                    servingSize: productData.servingSize,
                    ingredients: productData.ingredientsText,
                    imageSource: imageSource,
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

        func uploadNutritionCorrection(for item: FoodItem, comparedTo original: FoodItem.Nutriments?) async throws {
            guard let barcode = item.barcode?.trimmingCharacters(in: .whitespacesAndNewlines), !barcode.isEmpty
            else {
                throw OpenFoodFactsError.uploadFailed(nil)
            }

            guard let credentials = await Self.authStore.credentialsIfAvailable else {
                throw OpenFoodFactsError.uploadFailed(nil)
            }

            let writeURL = URL(string: "https://world.openfoodfacts.org/cgi/product_jqm2.pl")!
            var params: [String: String] = [
                "code": barcode,
                "user_id": credentials.username,
                "password": credentials.password,
                "action": "process",
                "nutrition_data": "on",
                "nutrition_data_per": item.nutriments.basis == .per100ml ? "100ml" : "100g",
                "comment": "Nutrition values corrected in Trio"
            ]

            let changedNutriments = changedNutrimentParameters(current: item.nutriments, original: original)
            guard !changedNutriments.isEmpty else {
                throw OpenFoodFactsError.uploadFailed(String(localized: "No nutrition changes to upload."))
            }
            params.merge(changedNutriments) { _, new in new }

            debug(
                .service,
                "OpenFoodFacts correction upload changed keys for code=\(barcode): \(changedNutriments.keys.sorted())"
            )

            var request = URLRequest(url: writeURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = formEncodedBody(params)
            request = try await applySessionCookie(to: request)

            let (data, response) = try await performRequestWithReauthentication(request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode
            else {
                if let httpResponse = response as? HTTPURLResponse {
                    let body = String(data: data, encoding: .utf8) ?? "<non-utf8-body>"
                    debug(
                        .service,
                        "OpenFoodFacts correction upload failed for code=\(barcode), status=\(httpResponse.statusCode), response=\(body)"
                    )
                }
                throw OpenFoodFactsError.invalidResponse
            }

            let rawResponse = String(data: data, encoding: .utf8) ?? "<non-utf8-body>"
            debug(
                .service,
                "OpenFoodFacts correction upload response for code=\(barcode), status=\(httpResponse.statusCode), response=\(rawResponse)"
            )

            if let writeResponse = try? JSONDecoder().decode(WriteAPIResponse.self, from: data) {
                debug(
                    .service,
                    "OpenFoodFacts parsed correction response for code=\(barcode): status=\(String(describing: writeResponse.status)), statusVerbose=\(String(describing: writeResponse.statusVerbose)), resultId=\(String(describing: writeResponse.result?.id))"
                )
                if let status = writeResponse.status, status != 1 {
                    throw OpenFoodFactsError.uploadFailed(writeResponse.statusVerbose)
                }
                if let result = writeResponse.result, result.id == "product_not_saved" {
                    throw OpenFoodFactsError.uploadFailed(writeResponse.statusVerbose)
                }
            }

            debug(.service, "OpenFoodFacts correction upload succeeded for code=\(barcode)")
        }

        private func formattedNutriment(_ value: Double?) -> String {
            guard let value else { return "0" }
            return String(format: "%.3f", value)
        }

        private func changedNutrimentParameters(
            current: FoodItem.Nutriments,
            original: FoodItem.Nutriments?,
            tolerance: Double = 0.0001
        ) -> [String: String] {
            var params: [String: String] = [:]

            func didChange(_ currentValue: Double?, _ originalValue: Double?) -> Bool {
                switch (currentValue, originalValue) {
                case (nil, nil):
                    return false
                case let (c?, o?):
                    return abs(c - o) > tolerance
                default:
                    return true
                }
            }

            func addNutriment(_ key: String, unit: String, currentValue: Double?, originalValue: Double?) {
                guard didChange(currentValue, originalValue) else { return }

                // Send explicit 0 only when user changed the value to 0.
                params["nutriment_\(key)"] = formattedNutriment(currentValue)
                params["nutriment_\(key)_unit"] = unit
            }

            addNutriment(
                "carbohydrates",
                unit: "g",
                currentValue: current.carbohydratesPer100g,
                originalValue: original?.carbohydratesPer100g
            )
            addNutriment(
                "fat",
                unit: "g",
                currentValue: current.fatPer100g,
                originalValue: original?.fatPer100g
            )
            addNutriment(
                "proteins",
                unit: "g",
                currentValue: current.proteinPer100g,
                originalValue: original?.proteinPer100g
            )
            addNutriment(
                "sugars",
                unit: "g",
                currentValue: current.sugarsPer100g,
                originalValue: original?.sugarsPer100g
            )
            addNutriment(
                "fiber",
                unit: "g",
                currentValue: current.fiberPer100g,
                originalValue: original?.fiberPer100g
            )
            addNutriment(
                "energy-kcal",
                unit: "kcal",
                currentValue: current.energyKcalPer100g,
                originalValue: original?.energyKcalPer100g
            )

            return params
        }

        private func formEncodedBody(_ params: [String: String]) -> Data? {
            var components = URLComponents()
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            return components.percentEncodedQuery?.data(using: .utf8)
        }

        private func applySessionCookie(to request: URLRequest) async throws -> URLRequest {
            var authorizedRequest = request

            if let cookieHeader = await Self.authStore.validSessionCookieHeader() {
                authorizedRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                return authorizedRequest
            }

            if await Self.authStore.hasCredentials {
                _ = try await login()
                if let cookieHeader = await Self.authStore.validSessionCookieHeader() {
                    authorizedRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                }
            }

            return authorizedRequest
        }

        private func performRequestWithReauthentication(_ request: URLRequest) async throws -> (Data, URLResponse) {
            let firstAttempt = try await URLSession.shared.data(for: request)

            guard let firstResponse = firstAttempt.1 as? HTTPURLResponse else {
                throw OpenFoodFactsError.invalidResponse
            }

            let shouldReauthenticate = firstResponse.statusCode == 401
                || firstResponse.statusCode == 403
                || firstResponse.statusCode == 503

            guard shouldReauthenticate else {
                return firstAttempt
            }

            guard await Self.authStore.hasCredentials else {
                return firstAttempt
            }

            let loginSucceeded = try await login()
            guard loginSucceeded else {
                return firstAttempt
            }

            let retryRequest = try await applySessionCookie(to: request)
            return try await URLSession.shared.data(for: retryRequest)
        }
    }
}

// MARK: - Errors

extension BarcodeScanner {
    enum OpenFoodFactsError: LocalizedError {
        case invalidResponse
        case productNotFound
        case uploadFailed(String?)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                String(localized: "Unable to reach OpenFoodFacts. Please try again.")
            case .productNotFound:
                String(
                    localized:
                    "We couldn’t find this barcode in OpenFoodFacts. Maybe add the product to OpenFoodFacts via the App."
                )
            case let .uploadFailed(reason):
                reason?.nonEmpty ?? String(localized: "Upload to OpenFoodFacts failed. Please try again.")
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

    /// Response structure for search API endpoint
    struct SearchAPIResponse: Decodable {
        let count: Int
        let page: Int
        let pageSize: Int
        let products: [ProductData]
    }

    struct WriteAPIResponse: Decodable {
        struct WriteResult: Decodable {
            let id: String?
            let lcName: String?

            enum CodingKeys: String, CodingKey {
                case id
                case lcName = "lc_name"
            }
        }

        let status: Int?
        let statusVerbose: String?
        let result: WriteResult?

        enum CodingKeys: String, CodingKey {
            case status
            case statusVerbose = "status_verbose"
            case result
        }
    }

    struct ProductData: Decodable {
        let code: String?
        let productName: String?
        let brands: String?
        let quantity: String?
        let productQuantityUnit: String?
        let servingSize: String?
        let servingQuantity: Double?
        let servingQuantityUnit: String?
        let productQuantity: Double?
        let ingredientsText: String?
        let imageUrl: String?
        let imageFrontUrl: String?
        let imageFrontThumbUrl: String?
        let nutriments: NutrimentsData?

        private enum CodingKeys: String, CodingKey {
            case code
            case productName
            case brands
            case quantity
            case productQuantityUnit
            case servingSize
            case servingQuantity
            case productQuantity
            case servingQuantityUnit
            case ingredientsText
            case imageUrl
            case imageFrontUrl
            case imageFrontThumbUrl
            case nutriments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decodeIfPresent(String.self, forKey: .code)
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
            } else if let stringValue = try? container.decodeIfPresent(
                String.self, forKey: .servingQuantity
            ),
                let parsed = Double(stringValue.replacingOccurrences(of: ",", with: "."))
            {
                servingQuantity = parsed
            } else {
                servingQuantity = nil
            }

            // Handle productQuantity (can be Double or String)
            if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: .productQuantity) {
                productQuantity = doubleValue
            } else if let stringValue = try? container.decodeIfPresent(
                String.self, forKey: .productQuantity
            ),
                let parsed = Double(stringValue.replacingOccurrences(of: ",", with: "."))
            {
                productQuantity = parsed
            } else {
                productQuantity = nil
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
        let basis: BarcodeScanner.FoodItem.Nutriments.Basis
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
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

private actor OpenFoodFactsAuthStore {
    private let defaults = UserDefaults.standard
    private let usernameKey = "openFoodFactsUsername"
    private let passwordKey = "openFoodFactsPassword"
    private let cookieNameKey = "openFoodFactsSessionCookieName"
    private let cookieValueKey = "openFoodFactsSessionCookieValue"
    private let cookieExpiryKey = "openFoodFactsSessionCookieExpiry"

    private(set) var credentialsIfAvailable: Credentials?
    private var sessionCookie: SessionCookie?

    init() {
        let username = defaults.string(forKey: usernameKey) ?? ""
        let password = defaults.string(forKey: passwordKey) ?? ""
        if !username.isEmpty, !password.isEmpty {
            credentialsIfAvailable = Credentials(username: username, password: password)
        }

        if let cookieName = defaults.string(forKey: cookieNameKey),
           let cookieValue = defaults.string(forKey: cookieValueKey)
        {
            let cookieExpiry = defaults.object(forKey: cookieExpiryKey) as? Date
            sessionCookie = SessionCookie(name: cookieName, value: cookieValue, expiresAt: cookieExpiry)
        }
    }

    var hasCredentials: Bool {
        credentialsIfAvailable != nil
    }

    func setCredentials(username: String, password: String) {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUsername.isEmpty || password.isEmpty {
            credentialsIfAvailable = nil
            defaults.removeObject(forKey: usernameKey)
            defaults.removeObject(forKey: passwordKey)
            clearStoredSessionCookie()
            clearOpenFoodFactsCookiesFromStorage()
            return
        }

        if let existingCredentials = credentialsIfAvailable,
           existingCredentials.username != trimmedUsername || existingCredentials.password != password
        {
            clearStoredSessionCookie()
            clearOpenFoodFactsCookiesFromStorage()
        }

        let credentials = Credentials(username: trimmedUsername, password: password)
        credentialsIfAvailable = credentials
        defaults.set(credentials.username, forKey: usernameKey)
        defaults.set(credentials.password, forKey: passwordKey)
    }

    func storeSessionCookie(_ cookie: HTTPCookie) {
        let storedCookie = SessionCookie(name: cookie.name, value: cookie.value, expiresAt: cookie.expiresDate)
        sessionCookie = storedCookie
        defaults.set(storedCookie.name, forKey: cookieNameKey)
        defaults.set(storedCookie.value, forKey: cookieValueKey)
        if let expiresAt = storedCookie.expiresAt {
            defaults.set(expiresAt, forKey: cookieExpiryKey)
        } else {
            defaults.removeObject(forKey: cookieExpiryKey)
        }
    }

    func hasValidSessionCookie(referenceDate: Date = Date()) -> Bool {
        validSessionCookieHeader(referenceDate: referenceDate) != nil
    }

    func validSessionCookieHeader(referenceDate: Date = Date()) -> String? {
        guard let sessionCookie else {
            return nil
        }

        if let expiresAt = sessionCookie.expiresAt, expiresAt <= referenceDate {
            clearStoredSessionCookie()
            return nil
        }

        return "\(sessionCookie.name)=\(sessionCookie.value)"
    }

    private func clearStoredSessionCookie() {
        sessionCookie = nil
        defaults.removeObject(forKey: cookieNameKey)
        defaults.removeObject(forKey: cookieValueKey)
        defaults.removeObject(forKey: cookieExpiryKey)
    }

    private func clearOpenFoodFactsCookiesFromStorage() {
        guard let cookies = HTTPCookieStorage.shared.cookies else {
            return
        }

        for cookie in cookies where cookie.domain.localizedCaseInsensitiveContains("openfoodfacts.org") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }
}

private extension OpenFoodFactsAuthStore {
    struct Credentials {
        let username: String
        let password: String
    }

    struct SessionCookie {
        let name: String
        let value: String
        let expiresAt: Date?
    }
}
