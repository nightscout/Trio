import Foundation
import os.log

// MARK: - Error Types

/// Errors that can occur during OpenAI API operations
enum OpenAIServiceError: LocalizedError {
    case missingAPIKey
    case invalidImageData
    case networkError(Error)
    case invalidResponse(statusCode: Int)
    case decodingError(Error)
    case noContentInResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return NSLocalizedString("OpenAI API key is not configured", comment: "Error when OpenAI API key is missing")
        case .invalidImageData:
            return NSLocalizedString("Unable to process the selected image", comment: "Error when image data is invalid")
        case let .networkError(error):
            return String(
                format: NSLocalizedString("Network error: %@", comment: "Network error with description"),
                error.localizedDescription
            )
        case let .invalidResponse(statusCode):
            return String(
                format: NSLocalizedString("Server returned error (status %d)", comment: "Server error with status code"),
                statusCode
            )
        case .decodingError:
            return NSLocalizedString("Unable to parse the AI response", comment: "Error when response parsing fails")
        case .noContentInResponse:
            return NSLocalizedString("No content returned from AI", comment: "Error when AI returns empty response")
        }
    }
}

// MARK: - Domain Types

/// Absorption time category for carbohydrate absorption
enum AbsorptionTimeCategory: String, Codable, CaseIterable {
    /// Fast absorption (30 min) - Simple sugars, fruits, juices, candy, soft drinks
    case fast

    /// Medium absorption (3 hours) - Starches, bread, rice, pasta, mixed meals, vegetables
    case medium

    /// Slow absorption (5 hours) - High-fat/protein foods: pizza, burgers, cheese, nuts, fatty meals
    case slow

    /// Other (3 hours default) - Alcoholic beverages, coffee, tea, or items where absorption is variable
    case other

    /// Returns the typical absorption duration in hours
    var typicalHours: Double {
        switch self {
        case .fast: return 0.5 // 30 minutes
        case .medium: return 3.0 // 3 hours
        case .slow: return 5.0 // 5 hours
        case .other: return 3.0 // 3 hours (default)
        }
    }
}

// MARK: - OpenAI API Request Types (Codable)

/// Root request body for OpenAI Chat Completions API
struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let maxTokens: Int
    let responseFormat: OpenAIResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

/// A message in the OpenAI chat conversation
struct OpenAIMessage: Encodable {
    let role: String
    let content: [OpenAIMessageContent]
}

/// Content item within a message (text or image)
enum OpenAIMessageContent: Encodable {
    case text(String)
    case imageUrl(OpenAIImageUrl)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageUrl(imageUrl):
            try container.encode("image_url", forKey: .type)
            try container.encode(imageUrl, forKey: .imageUrl)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
    }
}

/// Image URL content for vision API
struct OpenAIImageUrl: Encodable {
    let url: String
}

/// Response format specification for structured outputs
struct OpenAIResponseFormat: Encodable {
    let type: String
    let jsonSchema: OpenAIJSONSchema

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

/// JSON Schema specification for structured outputs
struct OpenAIJSONSchema: Encodable {
    let name: String
    let strict: Bool
    let schema: JSONSchemaDefinition
}

/// JSON Schema definition (supports nested object definitions)
struct JSONSchemaDefinition: Encodable {
    let type: String
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
    let items: JSONSchemaProperty?
    let additionalProperties: Bool?
    let `enum`: [String]?
    let description: String?

    init(
        type: String,
        properties: [String: JSONSchemaProperty]? = nil,
        required: [String]? = nil,
        items: JSONSchemaProperty? = nil,
        additionalProperties: Bool? = nil,
        enum enumValues: [String]? = nil,
        description: String? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.items = items
        self.additionalProperties = additionalProperties
        self.enum = enumValues
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case items
        case additionalProperties
        case `enum`
        case description
    }
}

/// Property definition within a JSON schema
indirect enum JSONSchemaProperty: Encodable {
    case string(description: String? = nil)
    case number(description: String? = nil)
    case boolean(description: String? = nil)
    case `enum`(values: [String], description: String? = nil)
    case array(items: JSONSchemaProperty, description: String? = nil)
    case object(properties: [String: JSONSchemaProperty], required: [String], description: String? = nil)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .string(description):
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)

        case let .number(description):
            try container.encode("number", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)

        case let .boolean(description):
            try container.encode("boolean", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)

        case let .enum(values, description):
            try container.encode("string", forKey: .type)
            try container.encode(values, forKey: .enumValues)
            try container.encodeIfPresent(description, forKey: .description)

        case let .array(items, description):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(description, forKey: .description)

        case let .object(properties, required, description):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
            try container.encode(false, forKey: .additionalProperties)
            try container.encodeIfPresent(description, forKey: .description)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case items
        case properties
        case required
        case additionalProperties
    }
}

// MARK: - OpenAI API Response Types (Codable)

/// Root response from OpenAI Chat Completions API
struct OpenAIChatResponse: Decodable {
    let id: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

/// A choice in the API response
struct OpenAIChoice: Decodable {
    let index: Int
    let message: OpenAIResponseMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

/// Message content in the response
struct OpenAIResponseMessage: Decodable {
    let role: String
    let content: String?
}

/// Token usage information
struct OpenAIUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - AI Response Content Types (what we parse from the content field)

/// Response structure for multi-item food analysis (matches our JSON schema)
struct AIFoodAnalysisResponse: Decodable {
    let foodItems: [AIFoodItemResponse]
    let overallConfidence: Double
    let reasoning: String?
}

/// Response structure for multi-item food analysis with reasoning
struct AIFoodAnalysisWithReasoningResponse: Decodable {
    let foodItems: [AIFoodItemResponse]
    let overallConfidence: Double
    let reasoning: String
}

/// Response structure for single item update
struct AISingleItemUpdateAPIResponse: Decodable {
    let updatedCarbs: Double
    let reasoning: String
    let updatedAbsorptionTime: String?
}

/// Response structure for conversation turn
struct AIConversationTurnAPIResponse: Decodable {
    let foodItems: [AIFoodItemWithIdResponse]
    let updatedItemIds: [String]
    let assistantMessage: String
    let overallConfidence: Double
}

/// Individual food item in the AI response
struct AIFoodItemResponse: Decodable {
    let name: String
    let carbs: Double
    let emoji: String
    let absorptionTime: String
}

/// Individual food item in conversation response (includes ID)
struct AIFoodItemWithIdResponse: Decodable {
    let id: String
    let name: String
    let carbs: Double
    let emoji: String
    let absorptionTime: String
}

/// Response from OpenAI Vision API containing carb estimate and food description (legacy single-item)
struct OpenAICarbEstimateResponse {
    let estimatedCarbs: Double
    let foodDescription: String
    let emoji: String
    let detailedDescription: String
    let absorptionTime: AbsorptionTimeCategory
    let carbConfidence: Double
    let absorptionConfidence: Double
    let emojiConfidence: Double
}

// MARK: - OpenAI Service

/// Service for interacting with OpenAI Vision API to analyze food images
final class OpenAIService {
    static let shared = OpenAIService()

    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "OpenAIService")
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Retrieves the OpenAI API key from the app's Info.plist (configured via LoopConfigOverride.xcconfig)
    private func getAPIKey() throws -> String {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String,
              !apiKey.isEmpty,
              apiKey != "$(OPENAI_API_KEY)"
        else {
            os_log("OpenAI API key not configured in LoopConfigOverride.xcconfig", log: log, type: .error)
            throw OpenAIServiceError.missingAPIKey
        }
        return apiKey
    }

    // MARK: - Multi-Item Food Analysis (Structured Outputs)

    /// Analyzes a food image and returns an array of individual food items detected
    /// Uses OpenAI Structured Outputs to guarantee response format
    /// - Parameter imageData: JPEG image data of the food to analyze
    /// - Returns: AIFoodItemsResponse containing all detected food items
    func estimateCarbsMultiItem(from imageData: Data) async throws -> AIFoodItemsResponse {
        let apiKey = try getAPIKey()
        let base64Image = imageData.base64EncodedString()

        os_log("Sending food image for multi-item AI analysis (%d bytes)", log: log, type: .info, imageData.count)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Analyze this food image for a diabetes insulin dosing app. Identify ALL individual food items visible and estimate carbohydrate content for each.

        ABSORPTION TIME CATEGORIES (assign to each item based on its composition):
        - "fast" (30 min): Simple sugars, fruits, juices, candy, soft drinks, honey, ice cream
        - "medium" (3 hours): Starches, bread, rice, pasta, mixed meals, vegetables, sandwiches, tacos
        - "slow" (5 hours): High-fat/protein foods - pizza, burgers, cheese, bacon, nuts, steak, avocado
        - "other" (3 hours): Alcoholic beverages, coffee, tea, or items where absorption is variable

        IMPORTANT GUIDELINES:
        - List EACH distinct food item separately (e.g., for a meal with sandwich, apple, and drink - list all 3)
        - Include sides, drinks, sauces, and condiments as separate items
        - For composite items like sandwiches, list as one item but note components in the name
        - Estimate portion sizes based on visual cues
        - Choose 1-2 emojis per item that best represent it
        """

        // Build the request with structured output schema
        let chatRequest = OpenAIChatRequest(
            model: "gpt-4o",
            messages: [
                OpenAIMessage(
                    role: "user",
                    content: [
                        .text(prompt),
                        .imageUrl(OpenAIImageUrl(url: "data:image/jpeg;base64,\(base64Image)"))
                    ]
                )
            ],
            maxTokens: 1000,
            responseFormat: OpenAIResponseFormat(
                type: "json_schema",
                jsonSchema: OpenAIJSONSchema(
                    name: "food_analysis",
                    strict: true,
                    schema: buildFoodAnalysisSchema()
                )
            )
        )

        request.httpBody = try encoder.encode(chatRequest)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse(statusCode: 0)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            os_log("OpenAI API error: status %d", log: log, type: .error, httpResponse.statusCode)
            if let errorBody = String(data: data, encoding: .utf8) {
                os_log("Error body: %{public}@", log: log, type: .error, errorBody)
            }
            throw OpenAIServiceError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        return try parseMultiItemResponse(data)
    }

    /// Builds the JSON schema for food analysis structured output
    private func buildFoodAnalysisSchema() -> JSONSchemaDefinition {
        let foodItemSchema = JSONSchemaProperty.object(
            properties: [
                "name": .string(description: "Concise item description, max 30 chars"),
                "carbs": .number(description: "Estimated carbohydrates in grams"),
                "emoji": .string(description: "1-2 food emojis representing the item"),
                "absorptionTime": .enum(
                    values: AbsorptionTimeCategory.allCases.map(\.rawValue),
                    description: "Absorption speed category"
                )
            ],
            required: ["name", "carbs", "emoji", "absorptionTime"],
            description: "A single food item detected in the image"
        )

        return JSONSchemaDefinition(
            type: "object",
            properties: [
                "foodItems": .array(items: foodItemSchema, description: "Array of all food items detected"),
                "overallConfidence": .number(description: "Overall confidence in the analysis (0.0-1.0)")
            ],
            required: ["foodItems", "overallConfidence"],
            additionalProperties: false
        )
    }

    /// Parses the OpenAI API response for multi-item food analysis
    private func parseMultiItemResponse(_ data: Data) throws -> AIFoodItemsResponse {
        // First decode the outer OpenAI response structure
        let chatResponse: OpenAIChatResponse
        do {
            chatResponse = try decoder.decode(OpenAIChatResponse.self, from: data)
        } catch {
            os_log("Failed to decode OpenAI response: %{public}@", log: log, type: .error, error.localizedDescription)
            throw OpenAIServiceError.decodingError(error)
        }

        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noContentInResponse
        }

        os_log("Received multi-item AI response content: %{public}@", log: log, type: .debug, content)

        // Decode the content JSON (guaranteed to match schema due to structured outputs)
        guard let contentData = content.data(using: .utf8) else {
            throw OpenAIServiceError
                .decodingError(NSError(
                    domain: "OpenAIService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid content encoding"]
                ))
        }

        let analysisResponse: AIFoodAnalysisResponse
        do {
            analysisResponse = try decoder.decode(AIFoodAnalysisResponse.self, from: contentData)
        } catch {
            os_log("Failed to decode food analysis: %{public}@", log: log, type: .error, error.localizedDescription)
            throw OpenAIServiceError.decodingError(error)
        }

        // Convert to our domain model
        let foodItems = analysisResponse.foodItems.map { item in
            AIFoodItem(
                name: item.name,
                carbs: item.carbs,
                emoji: item.emoji,
                absorptionTime: AbsorptionTimeCategory(rawValue: item.absorptionTime) ?? .medium
            )
        }

        guard !foodItems.isEmpty else {
            throw OpenAIServiceError
                .decodingError(NSError(
                    domain: "OpenAIService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No food items found in response"]
                ))
        }

        os_log(
            "AI detected %d food items with total %.1f grams of carbs",
            log: log,
            type: .info,
            foodItems.count,
            foodItems.reduce(0) { $0 + $1.carbs }
        )

        return AIFoodItemsResponse(
            foodItems: foodItems,
            overallConfidence: analysisResponse.overallConfidence
        )
    }

    // MARK: - Legacy Single-Item Analysis (kept for backwards compatibility)

    /// Analyzes a food image and returns estimated carbohydrate content
    /// - Parameter imageData: JPEG image data of the food to analyze
    /// - Returns: OpenAICarbEstimateResponse containing carb estimate and description
    func estimateCarbs(from imageData: Data) async throws -> OpenAICarbEstimateResponse {
        let apiKey = try getAPIKey()
        let base64Image = imageData.base64EncodedString()

        os_log("Sending food image for AI analysis (%d bytes)", log: log, type: .info, imageData.count)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Analyze this food image for a diabetes insulin dosing app. Estimate carbohydrate content and absorption characteristics.

        ABSORPTION TIME CATEGORIES:
        - "fast" (30 min): Simple sugars, fruits, juices, candy, soft drinks, honey, ice cream
        - "medium" (3 hours): Starches, bread, rice, pasta, mixed meals, vegetables, sandwiches, tacos
        - "slow" (5 hours): High-fat/protein foods - pizza, burgers, cheese, bacon, nuts, steak, avocado
        - "other" (3 hours): Alcoholic beverages, coffee, tea, or items where absorption is variable

        EMOJI SELECTION:
        Choose 1-3 food emojis that best represent the meal. Use only standard food/drink emojis.

        FOOD DESCRIPTION RULES:
        - If emojis completely represent the food (e.g., 🍕 for pizza), use ONLY the emoji(s) as the description
        - If emojis partially represent it, combine emoji + brief text (e.g., "🍝 Carbonara")
        - If no good emoji match exists, use brief text description (max 25 chars)

        Respond ONLY with valid JSON in this exact format (no other text):
        {
            "estimatedCarbs": <number in grams>,
            "foodDescription": "<emoji-only OR emoji+text OR text, max 25 chars>",
            "emoji": "<1-3 food emojis>",
            "detailedDescription": "<detailed description of food items and portions observed>",
            "absorptionTime": "<fast|medium|slow|other>",
            "carbConfidence": <0.0-1.0>,
            "absorptionConfidence": <0.0-1.0>,
            "emojiConfidence": <0.0-1.0>
        }
        """

        let chatRequest = OpenAIChatRequest(
            model: "gpt-4o",
            messages: [
                OpenAIMessage(
                    role: "user",
                    content: [
                        .text(prompt),
                        .imageUrl(OpenAIImageUrl(url: "data:image/jpeg;base64,\(base64Image)"))
                    ]
                )
            ],
            maxTokens: 500,
            responseFormat: nil // Legacy mode without structured outputs
        )

        request.httpBody = try encoder.encode(chatRequest)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse(statusCode: 0)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            os_log("OpenAI API error: status %d", log: log, type: .error, httpResponse.statusCode)
            if let errorBody = String(data: data, encoding: .utf8) {
                os_log("Error body: %{public}@", log: log, type: .error, errorBody)
            }
            throw OpenAIServiceError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        return try parseLegacyResponse(data)
    }

    /// Parses the legacy single-item response
    private func parseLegacyResponse(_ data: Data) throws -> OpenAICarbEstimateResponse {
        let chatResponse: OpenAIChatResponse
        do {
            chatResponse = try decoder.decode(OpenAIChatResponse.self, from: data)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }

        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noContentInResponse
        }

        os_log("Received AI response content: %{public}@", log: log, type: .debug, content)

        // Extract JSON from content (may be wrapped in markdown code blocks)
        let jsonString = extractJSON(from: content)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw OpenAIServiceError
                .decodingError(NSError(
                    domain: "OpenAIService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid content encoding"]
                ))
        }

        // Decode the legacy response structure
        let result: LegacySingleItemResponse
        do {
            result = try decoder.decode(LegacySingleItemResponse.self, from: jsonData)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }

        os_log(
            "AI estimated %{public}.1f grams of carbs (confidence: %.2f) for: %{public}@",
            log: log,
            type: .info,
            result.estimatedCarbs,
            result.carbConfidence,
            result.foodDescription
        )

        return OpenAICarbEstimateResponse(
            estimatedCarbs: result.estimatedCarbs,
            foodDescription: result.foodDescription,
            emoji: result.emoji,
            detailedDescription: result.detailedDescription,
            absorptionTime: AbsorptionTimeCategory(rawValue: result.absorptionTime) ?? .medium,
            carbConfidence: result.carbConfidence,
            absorptionConfidence: result.absorptionConfidence,
            emojiConfidence: result.emojiConfidence
        )
    }

    /// Extracts JSON from a string that might contain markdown code blocks
    private func extractJSON(from content: String) -> String {
        // Try to find JSON in code block first
        if let codeBlockRange = content.range(of: "```json"),
           let endRange = content.range(of: "```", range: codeBlockRange.upperBound ..< content.endIndex)
        {
            return String(content[codeBlockRange.upperBound ..< endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try plain code block
        if let codeBlockRange = content.range(of: "```"),
           let endRange = content.range(of: "```", range: codeBlockRange.upperBound ..< content.endIndex)
        {
            return String(content[codeBlockRange.upperBound ..< endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON object directly
        if let startBrace = content.firstIndex(of: "{"),
           let endBrace = content.lastIndex(of: "}")
        {
            return String(content[startBrace ... endBrace])
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Enhanced Food Analysis with Reasoning

    /// Analyzes a food image with optional user description and returns items with reasoning
    /// - Parameters:
    ///   - imageData: JPEG image data of the food to analyze
    ///   - userDescription: Optional context from user (e.g., "No sugar added dessert")
    /// - Returns: AIFoodItemsResponseWithReasoning containing items and explanation
    func analyzeFood(imageData: Data, userDescription: String?) async throws -> AIFoodItemsResponseWithReasoning {
        let apiKey = try getAPIKey()
        let base64Image = imageData.base64EncodedString()

        os_log("Sending food image for AI analysis with reasoning (%d bytes)", log: log, type: .info, imageData.count)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var prompt = """
        Analyze this food image for a diabetes insulin dosing app. Identify ALL individual food items visible and estimate carbohydrate content for each.

        ABSORPTION TIME CATEGORIES (assign to each item based on its composition):
        - "fast" (30 min): Simple sugars, fruits, juices, candy, soft drinks, honey, ice cream
        - "medium" (3 hours): Starches, bread, rice, pasta, mixed meals, vegetables, sandwiches, tacos
        - "slow" (5 hours): High-fat/protein foods - pizza, burgers, cheese, bacon, nuts, steak, avocado
        - "other" (3 hours): Alcoholic beverages, coffee, tea, or items where absorption is variable

        IMPORTANT GUIDELINES:
        - List EACH distinct food item separately (e.g., for a meal with sandwich, apple, and drink - list all 3)
        - Include sides, drinks, sauces, and condiments as separate items
        - For composite items like sandwiches, list as one item but note components in the name
        - Estimate portion sizes based on visual cues
        - Choose 1-2 emojis per item that best represent it
        - Provide a brief reasoning explaining your carb estimates
        """

        // Add user description if provided
        if let description = userDescription, !description.isEmpty {
            prompt += "\n\nUSER CONTEXT: \(description)\nPlease factor this information into your analysis."
        }

        let chatRequest = OpenAIChatRequest(
            model: "gpt-4o",
            messages: [
                OpenAIMessage(
                    role: "user",
                    content: [
                        .text(prompt),
                        .imageUrl(OpenAIImageUrl(url: "data:image/jpeg;base64,\(base64Image)"))
                    ]
                )
            ],
            maxTokens: 1500,
            responseFormat: OpenAIResponseFormat(
                type: "json_schema",
                jsonSchema: OpenAIJSONSchema(
                    name: "food_analysis_with_reasoning",
                    strict: true,
                    schema: buildFoodAnalysisWithReasoningSchema()
                )
            )
        )

        request.httpBody = try encoder.encode(chatRequest)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse(statusCode: 0)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            os_log("OpenAI API error: status %d", log: log, type: .error, httpResponse.statusCode)
            if let errorBody = String(data: data, encoding: .utf8) {
                os_log("Error body: %{public}@", log: log, type: .error, errorBody)
            }
            throw OpenAIServiceError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        return try parseMultiItemResponseWithReasoning(data)
    }

    /// Builds schema for food analysis with reasoning
    private func buildFoodAnalysisWithReasoningSchema() -> JSONSchemaDefinition {
        let foodItemSchema = JSONSchemaProperty.object(
            properties: [
                "name": .string(description: "Concise item description, max 30 chars"),
                "carbs": .number(description: "Estimated carbohydrates in grams"),
                "emoji": .string(description: "1-2 food emojis representing the item"),
                "absorptionTime": .enum(
                    values: AbsorptionTimeCategory.allCases.map(\.rawValue),
                    description: "Absorption speed category"
                )
            ],
            required: ["name", "carbs", "emoji", "absorptionTime"],
            description: "A single food item detected in the image"
        )

        return JSONSchemaDefinition(
            type: "object",
            properties: [
                "foodItems": .array(items: foodItemSchema, description: "Array of all food items detected"),
                "overallConfidence": .number(description: "Overall confidence in the analysis (0.0-1.0)"),
                "reasoning": .string(
                    description: "Brief explanation of how carb values were estimated, mentioning portion sizes and assumptions made"
                )
            ],
            required: ["foodItems", "overallConfidence", "reasoning"],
            additionalProperties: false
        )
    }

    /// Parses the response with reasoning
    private func parseMultiItemResponseWithReasoning(_ data: Data) throws -> AIFoodItemsResponseWithReasoning {
        let chatResponse: OpenAIChatResponse
        do {
            chatResponse = try decoder.decode(OpenAIChatResponse.self, from: data)
        } catch {
            os_log("Failed to decode OpenAI response: %{public}@", log: log, type: .error, error.localizedDescription)
            throw OpenAIServiceError.decodingError(error)
        }

        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noContentInResponse
        }

        os_log("Received AI response with reasoning: %{public}@", log: log, type: .debug, content)

        guard let contentData = content.data(using: .utf8) else {
            throw OpenAIServiceError
                .decodingError(NSError(
                    domain: "OpenAIService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid content encoding"]
                ))
        }

        let analysisResponse: AIFoodAnalysisWithReasoningResponse
        do {
            analysisResponse = try decoder.decode(AIFoodAnalysisWithReasoningResponse.self, from: contentData)
        } catch {
            os_log(
                "Failed to decode food analysis with reasoning: %{public}@",
                log: log,
                type: .error,
                error.localizedDescription
            )
            throw OpenAIServiceError.decodingError(error)
        }

        let foodItems = analysisResponse.foodItems.map { item in
            AIFoodItem(
                name: item.name,
                carbs: item.carbs,
                emoji: item.emoji,
                absorptionTime: AbsorptionTimeCategory(rawValue: item.absorptionTime) ?? .medium
            )
        }

        guard !foodItems.isEmpty else {
            throw OpenAIServiceError
                .decodingError(NSError(
                    domain: "OpenAIService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No food items found in response"]
                ))
        }

        os_log("AI detected %d food items with reasoning", log: log, type: .info, foodItems.count)

        return AIFoodItemsResponseWithReasoning(
            foodItems: foodItems,
            overallConfidence: analysisResponse.overallConfidence,
            reasoning: analysisResponse.reasoning
        )
    }

    // MARK: - Single Item Update (Inline Editing)

    /// Updates a single item's carb estimate based on new description
    /// - Parameters:
    ///   - imageData: Original image data
    ///   - currentItems: All current food items
    ///   - editedItemId: ID of the item being edited
    ///   - newDescription: New description for the item
    /// - Returns: Updated carb count and reasoning
    func updateSingleItem(
        imageData: Data,
        currentItems: [AIFoodItem],
        editedItemId: UUID,
        newDescription: String
    ) async throws -> AISingleItemUpdateResponse {
        let apiKey = try getAPIKey()
        let base64Image = imageData.base64EncodedString()

        guard let editedItem = currentItems.first(where: { $0.id == editedItemId }) else {
            throw OpenAIServiceError
                .decodingError(NSError(domain: "OpenAIService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Item not found"]))
        }

        os_log("Updating item '%{public}@' to '%{public}@'", log: log, type: .info, editedItem.name, newDescription)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build context of other items
        let otherItemsContext = currentItems
            .filter { $0.id != editedItemId }
            .map { "\($0.emoji ?? "") \($0.name): \(Int($0.carbs))g" }
            .joined(separator: ", ")

        let prompt = """
        I previously analyzed this food image and identified these items: \(otherItemsContext
            .isEmpty ? "none" : otherItemsContext)

        I also identified an item as "\(editedItem.name)" with \(Int(editedItem.carbs))g carbs.

        The user has corrected this item's description to: "\(newDescription)"

        Please re-estimate the carbohydrates for this corrected item based on the image and new description.
        Consider the visual portion size and the specific food type indicated by the user.

        ABSORPTION TIME CATEGORIES:
        - "fast": Simple sugars, fruits, juices
        - "medium": Starches, bread, rice, pasta
        - "slow": High-fat/protein foods
        - "other": Variable absorption
        """

        let chatRequest = OpenAIChatRequest(
            model: "gpt-4o",
            messages: [
                OpenAIMessage(
                    role: "user",
                    content: [
                        .text(prompt),
                        .imageUrl(OpenAIImageUrl(url: "data:image/jpeg;base64,\(base64Image)"))
                    ]
                )
            ],
            maxTokens: 500,
            responseFormat: OpenAIResponseFormat(
                type: "json_schema",
                jsonSchema: OpenAIJSONSchema(
                    name: "single_item_update",
                    strict: true,
                    schema: buildSingleItemUpdateSchema()
                )
            )
        )

        request.httpBody = try encoder.encode(chatRequest)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse(statusCode: 0)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            os_log("OpenAI API error: status %d", log: log, type: .error, httpResponse.statusCode)
            throw OpenAIServiceError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        return try parseSingleItemUpdateResponse(data, itemId: editedItemId)
    }

    /// Builds schema for single item update
    private func buildSingleItemUpdateSchema() -> JSONSchemaDefinition {
        JSONSchemaDefinition(
            type: "object",
            properties: [
                "updatedCarbs": .number(description: "Updated carbohydrate estimate in grams"),
                "reasoning": .string(description: "Brief explanation of the updated estimate"),
                "updatedAbsorptionTime": .enum(
                    values: AbsorptionTimeCategory.allCases.map(\.rawValue),
                    description: "Updated absorption time if it changed"
                )
            ],
            required: ["updatedCarbs", "reasoning", "updatedAbsorptionTime"],
            additionalProperties: false
        )
    }

    /// Parses single item update response
    private func parseSingleItemUpdateResponse(_ data: Data, itemId: UUID) throws -> AISingleItemUpdateResponse {
        let chatResponse: OpenAIChatResponse
        do {
            chatResponse = try decoder.decode(OpenAIChatResponse.self, from: data)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }

        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noContentInResponse
        }

        guard let contentData = content.data(using: .utf8) else {
            throw OpenAIServiceError
                .decodingError(NSError(
                    domain: "OpenAIService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid content encoding"]
                ))
        }

        let apiResponse: AISingleItemUpdateAPIResponse
        do {
            apiResponse = try decoder.decode(AISingleItemUpdateAPIResponse.self, from: contentData)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }

        os_log("Item updated to %.1fg carbs", log: log, type: .info, apiResponse.updatedCarbs)

        return AISingleItemUpdateResponse(
            itemId: itemId,
            updatedCarbs: apiResponse.updatedCarbs,
            reasoning: apiResponse.reasoning,
            updatedAbsorptionTime: apiResponse.updatedAbsorptionTime.flatMap { AbsorptionTimeCategory(rawValue: $0) }
        )
    }

    // MARK: - Conversation Turn

    /// Processes a conversation turn with the AI
    /// - Parameters:
    ///   - imageData: Original image data
    ///   - currentItems: Current food items
    ///   - conversationHistory: Previous messages in the conversation
    ///   - userMessage: The user's new message
    /// - Returns: Updated items and assistant response
    func conversationTurn(
        imageData: Data,
        currentItems: [AIFoodItem],
        conversationHistory: [AIConversationMessage],
        userMessage: String
    ) async throws -> AIConversationResponse {
        let apiKey = try getAPIKey()
        let base64Image = imageData.base64EncodedString()

        os_log("Processing conversation turn: %{public}@", log: log, type: .info, userMessage)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build current items context
        let itemsContext = currentItems.enumerated().map { index, item in
            "[\(index + 1)] \(item.emoji ?? "") \(item.name): \(Int(item.carbs))g (\(item.absorptionTime.rawValue))"
        }.joined(separator: "\n")

        // Build conversation history (text only, skip carb summaries)
        let historyText = conversationHistory.compactMap { msg -> String? in
            switch msg.content {
            case let .text(text):
                return "\(msg.role.rawValue.capitalized): \(text)"
            case let .systemEvent(event):
                return "System: \(event)"
            case .carbSummary:
                return nil
            }
        }.joined(separator: "\n")

        let systemPrompt = """
        You are helping a person with diabetes refine their carbohydrate estimates for insulin dosing.

        CURRENT FOOD ITEMS:
        \(itemsContext)

        CONVERSATION HISTORY:
        \(historyText)

        The user's new message is below. Based on their feedback:
        1. Update any food items that need to change
        2. Keep item IDs consistent (return the same IDs for unchanged items)
        3. Provide a helpful response acknowledging their input
        4. If they mention specific items, update those
        5. If they provide new information about the whole meal, adjust accordingly

        For each item, return:
        - id: The original UUID if updating, or generate a new one for new items
        - name: Food description (max 30 chars)
        - carbs: Estimated grams
        - emoji: 1-2 relevant emojis
        - absorptionTime: fast/medium/slow/other

        ABSORPTION TIME CATEGORIES:
        - "fast": Simple sugars, fruits, juices
        - "medium": Starches, bread, rice, pasta
        - "slow": High-fat/protein foods
        - "other": Variable absorption
        """

        // Build messages array for multi-turn conversation
        var messages: [OpenAIMessage] = [
            OpenAIMessage(
                role: "system",
                content: [.text(systemPrompt)]
            ),
            OpenAIMessage(
                role: "user",
                content: [
                    .text("Here is the food image for reference:"),
                    .imageUrl(OpenAIImageUrl(url: "data:image/jpeg;base64,\(base64Image)"))
                ]
            ),
            OpenAIMessage(
                role: "user",
                content: [.text(userMessage)]
            )
        ]

        let chatRequest = OpenAIChatRequest(
            model: "gpt-4o",
            messages: messages,
            maxTokens: 1500,
            responseFormat: OpenAIResponseFormat(
                type: "json_schema",
                jsonSchema: OpenAIJSONSchema(
                    name: "conversation_response",
                    strict: true,
                    schema: buildConversationResponseSchema()
                )
            )
        )

        request.httpBody = try encoder.encode(chatRequest)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse(statusCode: 0)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            os_log("OpenAI API error: status %d", log: log, type: .error, httpResponse.statusCode)
            throw OpenAIServiceError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        return try parseConversationResponse(data, originalItems: currentItems)
    }

    /// Builds schema for conversation response
    private func buildConversationResponseSchema() -> JSONSchemaDefinition {
        let foodItemSchema = JSONSchemaProperty.object(
            properties: [
                "id": .string(description: "UUID of the item (same as original if updating, new UUID if adding)"),
                "name": .string(description: "Concise item description, max 30 chars"),
                "carbs": .number(description: "Estimated carbohydrates in grams"),
                "emoji": .string(description: "1-2 food emojis representing the item"),
                "absorptionTime": .enum(
                    values: AbsorptionTimeCategory.allCases.map(\.rawValue),
                    description: "Absorption speed category"
                )
            ],
            required: ["id", "name", "carbs", "emoji", "absorptionTime"],
            description: "A food item"
        )

        return JSONSchemaDefinition(
            type: "object",
            properties: [
                "foodItems": .array(items: foodItemSchema, description: "All food items (updated list)"),
                "updatedItemIds": .array(items: .string(), description: "IDs of items that were changed in this turn"),
                "assistantMessage": .string(description: "Helpful response to the user acknowledging their input"),
                "overallConfidence": .number(description: "Overall confidence in the updated analysis (0.0-1.0)")
            ],
            required: ["foodItems", "updatedItemIds", "assistantMessage", "overallConfidence"],
            additionalProperties: false
        )
    }

    /// Parses conversation response
    private func parseConversationResponse(_ data: Data, originalItems _: [AIFoodItem]) throws -> AIConversationResponse {
        let chatResponse: OpenAIChatResponse
        do {
            chatResponse = try decoder.decode(OpenAIChatResponse.self, from: data)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }

        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIServiceError.noContentInResponse
        }

        guard let contentData = content.data(using: .utf8) else {
            throw OpenAIServiceError
                .decodingError(NSError(
                    domain: "OpenAIService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid content encoding"]
                ))
        }

        let apiResponse: AIConversationTurnAPIResponse
        do {
            apiResponse = try decoder.decode(AIConversationTurnAPIResponse.self, from: contentData)
        } catch {
            throw OpenAIServiceError.decodingError(error)
        }

        // Convert API response items to domain model
        let foodItems = apiResponse.foodItems.map { item in
            AIFoodItem(
                id: UUID(uuidString: item.id) ?? UUID(),
                name: item.name,
                carbs: item.carbs,
                emoji: item.emoji,
                absorptionTime: AbsorptionTimeCategory(rawValue: item.absorptionTime) ?? .medium
            )
        }

        let updatedItemIds = apiResponse.updatedItemIds.compactMap { UUID(uuidString: $0) }

        os_log("Conversation turn: %d items, %d updated", log: log, type: .info, foodItems.count, updatedItemIds.count)

        return AIConversationResponse(
            foodItems: foodItems,
            updatedItemIds: updatedItemIds,
            assistantMessage: apiResponse.assistantMessage,
            overallConfidence: apiResponse.overallConfidence
        )
    }
}

// MARK: - Legacy Response Type

/// Response structure for legacy single-item analysis
private struct LegacySingleItemResponse: Decodable {
    let estimatedCarbs: Double
    let foodDescription: String
    let emoji: String
    let detailedDescription: String
    let absorptionTime: String
    let carbConfidence: Double
    let absorptionConfidence: Double
    let emojiConfidence: Double
}
