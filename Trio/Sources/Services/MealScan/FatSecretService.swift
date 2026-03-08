import Foundation
import UIKit

protocol FatSecretService {
    func recognizeImage(_ image: UIImage, eatenFoodIds: [String]) async throws -> [DetectedFood]
}

final class BaseFatSecretService: FatSecretService, Injectable {
    private let clientId: String
    private let clientSecret: String

    private var accessToken: String?
    private var tokenExpiry: Date?

    private let tokenURL = URL(string: "https://oauth.fatsecret.com/connect/token")!
    private let recognitionURL = URL(string: "https://platform.fatsecret.com/rest/image-recognition/v2")!

    init() {
        self.clientId = MealScanDevKeys.fatSecretClientId
        self.clientSecret = MealScanDevKeys.fatSecretClientSecret
    }

    // MARK: - Public

    func recognizeImage(_ image: UIImage, eatenFoodIds: [String]) async throws -> [DetectedFood] {
        let token = try await getValidToken()
        let base64Image = try prepareImage(image)
        return try await callRecognitionAPI(base64Image: base64Image, token: token, eatenFoodIds: eatenFoodIds)
    }

    // MARK: - OAuth2 Token

    private func getValidToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }
        return try await fetchNewToken()
    }

    private func fetchNewToken() async throws -> String {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(clientId):\(clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw FatSecretError.invalidCredentials
        }
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let body = "grant_type=client_credentials&scope=premier"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw FatSecretError.tokenRequestFailed
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        self.accessToken = tokenResponse.access_token
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in - 60))
        return tokenResponse.access_token
    }

    // MARK: - Image Preparation

    private func prepareImage(_ image: UIImage) throws -> String {
        let targetSize = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = resized.jpegData(compressionQuality: 0.8) else {
            throw FatSecretError.imageConversionFailed
        }

        let base64 = jpegData.base64EncodedString()
        guard base64.count <= 999_982 else {
            throw FatSecretError.imageTooLarge
        }

        return base64
    }

    // MARK: - Recognition API

    private func callRecognitionAPI(base64Image: String, token: String, eatenFoodIds: [String] = []) async throws -> [DetectedFood] {
        var request = URLRequest(url: recognitionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var requestBody: [String: Any] = [
            "image_b64": base64Image,
            "include_food_data": true,
            "region": "US",
            "language": "en"
        ]
        if !eatenFoodIds.isEmpty {
            requestBody["eaten_foods"] = eatenFoodIds.map { ["food_id": $0] }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FatSecretError.networkError
        }

        if httpResponse.statusCode == 401 {
            // Token expired, refresh and retry once
            accessToken = nil
            tokenExpiry = nil
            let newToken = try await fetchNewToken()
            return try await callRecognitionAPIOnce(base64Image: base64Image, token: newToken, eatenFoodIds: eatenFoodIds)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(FatSecretErrorResponse.self, from: data) {
                if errorResponse.error?.code == 211 {
                    throw FatSecretError.nutritionLabelDetected
                }
            }
            throw FatSecretError.apiError(statusCode: httpResponse.statusCode)
        }

        return try parseFoodResponse(data)
    }

    private func callRecognitionAPIOnce(base64Image: String, token: String, eatenFoodIds: [String] = []) async throws -> [DetectedFood] {
        var request = URLRequest(url: recognitionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var requestBody: [String: Any] = [
            "image_b64": base64Image,
            "include_food_data": true,
            "region": "US",
            "language": "en"
        ]
        if !eatenFoodIds.isEmpty {
            requestBody["eaten_foods"] = eatenFoodIds.map { ["food_id": $0] }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw FatSecretError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try parseFoodResponse(data)
    }

    // MARK: - Response Parsing

    private func parseFoodResponse(_ data: Data) throws -> [DetectedFood] {
        let response = try JSONDecoder().decode(FatSecretRecognitionResponse.self, from: data)

        guard let foodResponses = response.food_response, !foodResponses.isEmpty else {
            throw FatSecretError.noFoodDetected
        }

        return foodResponses.compactMap { item -> DetectedFood? in
            guard let eaten = item.eaten else { return nil }
            let nutrition = eaten.total_nutritional_content

            // Parse alternative servings from food.servings
            let alternativeServings: [ServingOption] = item.food?.servings?.serving.items.compactMap { serving in
                ServingOption(
                    id: serving.serving_id ?? UUID().uuidString,
                    description: serving.serving_description ?? "",
                    metricAmount: Double(serving.metric_serving_amount ?? "0") ?? 0,
                    metricUnit: serving.metric_serving_unit ?? "g",
                    numberOfUnits: serving.number_of_units ?? "1",
                    isDefault: serving.is_default == "1",
                    carbs: Decimal(string: serving.carbohydrate ?? "0") ?? 0,
                    fat: Decimal(string: serving.fat ?? "0") ?? 0,
                    protein: Decimal(string: serving.protein ?? "0") ?? 0,
                    calories: Decimal(string: serving.calories ?? "0") ?? 0,
                    sugar: Decimal(string: serving.sugar ?? "0") ?? 0
                )
            } ?? []

            return DetectedFood(
                foodId: item.food_id,
                name: item.food_entry_name ?? "Unknown food",
                foodType: item.food?.food_type ?? "Generic",
                nameSingular: eaten.food_name_singular ?? "",
                namePlural: eaten.food_name_plural ?? "",
                servingDescription: item.suggested_serving?.serving_description ?? "",
                portionGrams: eaten.total_metric_amount ?? 0,
                perUnitGrams: eaten.per_unit_metric_amount ?? 0,
                carbs: Decimal(string: nutrition?.carbohydrate ?? "0") ?? 0,
                fat: Decimal(string: nutrition?.fat ?? "0") ?? 0,
                protein: Decimal(string: nutrition?.protein ?? "0") ?? 0,
                calories: Decimal(string: nutrition?.calories ?? "0") ?? 0,
                sugar: Decimal(string: nutrition?.sugar ?? "0") ?? 0,
                fiber: Decimal(string: nutrition?.fiber ?? "0") ?? 0,
                alternativeServings: alternativeServings
            )
        }
    }
}

// MARK: - Error Types

enum FatSecretError: LocalizedError {
    case invalidCredentials
    case tokenRequestFailed
    case imageConversionFailed
    case imageTooLarge
    case networkError
    case apiError(statusCode: Int)
    case nutritionLabelDetected
    case noFoodDetected

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid FatSecret credentials"
        case .tokenRequestFailed: return "Failed to authenticate with FatSecret"
        case .imageConversionFailed: return "Failed to process image"
        case .imageTooLarge: return "Image is too large to process"
        case .networkError: return "Network error communicating with FatSecret"
        case .apiError(let code): return "FatSecret API error (code: \(code))"
        case .nutritionLabelDetected: return "Try photographing the actual food, not the nutrition label"
        case .noFoodDetected: return "No food detected in the image. Try photographing from above with better lighting."
        }
    }
}

// MARK: - Response Models

private struct OAuthTokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let token_type: String
}

private struct FatSecretRecognitionResponse: Decodable {
    let food_response: [FoodResponseItem]?
}

private struct FoodResponseItem: Decodable {
    let food_id: Int?
    let food_entry_name: String?
    let eaten: EatenData?
    let suggested_serving: SuggestedServingData?
    let food: FoodData?
}

private struct EatenData: Decodable {
    let total_metric_amount: Double?
    let total_nutritional_content: NutritionalContent?
    let food_name_singular: String?
    let food_name_plural: String?
    let per_unit_metric_amount: Double?
}

private struct NutritionalContent: Decodable {
    let calories: String?
    let carbohydrate: String?
    let protein: String?
    let fat: String?
    let fiber: String?
    let sugar: String?
}

private struct SuggestedServingData: Decodable {
    let serving_description: String?
    let number_of_units: String?
    let metric_serving_amount: String?
    let metric_serving_unit: String?
}

private struct FoodData: Decodable {
    let food_type: String?
    let servings: FoodServingsContainer?
}

private struct FoodServingsContainer: Decodable {
    let serving: FoodServingList

    // Handle both single object and array from FatSecret API
    enum FoodServingList: Decodable {
        case single(FoodServingItem)
        case multiple([FoodServingItem])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let array = try? container.decode([FoodServingItem].self) {
                self = .multiple(array)
            } else if let single = try? container.decode(FoodServingItem.self) {
                self = .single(single)
            } else {
                self = .multiple([])
            }
        }

        var items: [FoodServingItem] {
            switch self {
            case .single(let item): return [item]
            case .multiple(let items): return items
            }
        }
    }
}

private struct FoodServingItem: Decodable {
    let serving_id: String?
    let serving_description: String?
    let metric_serving_amount: String?
    let metric_serving_unit: String?
    let number_of_units: String?
    let is_default: String?
    let calories: String?
    let carbohydrate: String?
    let protein: String?
    let fat: String?
    let sugar: String?
}

private struct FatSecretErrorResponse: Decodable {
    let error: FatSecretAPIError?
}

private struct FatSecretAPIError: Decodable {
    let code: Int?
    let message: String?
}
