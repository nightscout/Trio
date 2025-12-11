import Combine
import Foundation
import UIKit

/// Service for communicating with the Claude API
final class ClaudeAPIService {
    enum APIError: LocalizedError {
        case noAPIKey
        case invalidURL
        case networkError(Error)
        case invalidResponse
        case apiError(String)
        case decodingError(Error)
        case imageProcessingError

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured. Please add your Claude API key in settings."
            case .invalidURL:
                return "Invalid API URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from server"
            case .apiError(let message):
                return "API error: \(message)"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .imageProcessingError:
                return "Failed to process image for analysis"
            }
        }
    }

    struct Message: Codable {
        let role: String
        let content: String
    }

    // MARK: - Vision API Structures

    /// Content block for vision API - can be text or image
    struct VisionContentBlock: Encodable {
        let type: String
        let text: String?
        let source: ImageSource?

        init(text: String) {
            self.type = "text"
            self.text = text
            self.source = nil
        }

        init(imageData: String, mediaType: String) {
            self.type = "image"
            self.text = nil
            self.source = ImageSource(type: "base64", media_type: mediaType, data: imageData)
        }

        struct ImageSource: Encodable {
            let type: String
            let media_type: String
            let data: String
        }
    }

    /// Message with vision content (array of content blocks)
    struct VisionMessage: Encodable {
        let role: String
        let content: [VisionContentBlock]
    }

    /// API request for vision (uses content array instead of string)
    struct VisionAPIRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [VisionMessage]
    }

    struct APIRequest: Codable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [Message]
    }

    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }

    struct APIResponse: Codable {
        let id: String
        let type: String
        let role: String
        let content: [ContentBlock]
        let model: String
        let stop_reason: String?

        var textContent: String {
            content.compactMap { $0.text }.joined()
        }
    }

    struct ErrorResponse: Codable {
        let type: String
        let error: ErrorDetail

        struct ErrorDetail: Codable {
            let type: String
            let message: String
        }
    }

    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-sonnet-4-20250514"
    private let apiVersion = "2023-06-01"

    /// System prompt for safety-focused diabetes analysis
    static let safetySystemPrompt = """
    You are a helpful AI assistant analyzing glucose and diabetes management data for educational purposes.

    IMPORTANT SAFETY GUIDELINES:
    - You are allowed to recommend specific insulin doses or exact amounts - but only after careful consideration of current levels, control, and the magnitude of change
    - Keep recommendations conservative and err on the side of small changes
    - Suggest follow-up to see how changes work before making additional adjustments
    - You may also suggest percentage-based adjustments (5-15%)
    - Flag dangerous patterns immediately (severe lows <54 mg/dL, potential DKA risk with high glucose + symptoms)
    - Be conservative in recommendations
    - Acknowledge limitations of the data and analysis

    When analyzing data:
    - Look for patterns by time of day
    - Identify post-meal glucose responses
    - Note any concerning trends (frequent lows, sustained highs)
    - Consider the relationship between carbs, insulin, and glucose
    - Be encouraging about what's working well, but also be clear about what is not working well
    - Assume large spikes without carbs entered are missed meals. Note this if frequent and encourage better meal logging.

    FORMATTING REQUIREMENTS:
    - Use **bold** for important numbers and key findings
    - Use sections with emoji headers like: 📊 📈 ⚠️ ✅ 💡 🎯 📋
    - Use bullet points for lists
    - Keep paragraphs short and scannable
    - For reports, use clear section dividers
    """

    /// System prompt for carb estimation from photos
    static let carbEstimationSystemPrompt = """
    You are a nutrition expert helping someone with Type 1 diabetes estimate carbohydrates from food photos.

    IMPORTANT GUIDELINES:
    - Be conservative in your estimates when uncertain
    - Round to the nearest 5g for simplicity
    - Consider standard portion sizes unless the user indicates otherwise
    - If you cannot identify a food clearly, ask for clarification or note the uncertainty
    - Always provide a single number for total carbs, not a range

    FORMATTING REQUIREMENTS:
    - List each food item clearly with its portion and carb estimate
    - Format: "🍽️ Food item (portion): ~Xg"
    - Provide a clear total at the end
    - Include a confidence level (Low/Medium/High)
    - Note any assumptions you're making
    """

    func sendMessage(
        messages: [Message],
        apiKey: String,
        systemPrompt: String? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }

        guard let url = URL(string: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let apiRequest = APIRequest(
            model: model,
            max_tokens: 4096,
            system: systemPrompt ?? Self.safetySystemPrompt,
            messages: messages
        )

        request.httpBody = try JSONEncoder().encode(apiRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.apiError(errorResponse.error.message)
            }
            throw APIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        do {
            let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
            return apiResponse.textContent
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Send a single message for quick analysis
    func analyze(prompt: String, apiKey: String, systemPrompt: String? = nil) async throws -> String {
        let messages = [Message(role: "user", content: prompt)]
        return try await sendMessage(messages: messages, apiKey: apiKey, systemPrompt: systemPrompt)
    }

    // MARK: - Vision API Methods

    /// Analyze an image with an optional text prompt
    /// - Parameters:
    ///   - image: The UIImage to analyze
    ///   - prompt: Text prompt to accompany the image
    ///   - apiKey: Claude API key
    ///   - systemPrompt: Optional custom system prompt
    /// - Returns: The AI response text
    func analyzeImage(
        image: UIImage,
        prompt: String,
        apiKey: String,
        systemPrompt: String? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }

        guard let url = URL(string: baseURL) else {
            throw APIError.invalidURL
        }

        // Resize and encode image
        guard let imageData = prepareImageForAPI(image) else {
            throw APIError.imageProcessingError
        }

        // Build content blocks: image first, then text
        var contentBlocks: [VisionContentBlock] = [
            VisionContentBlock(imageData: imageData.base64, mediaType: imageData.mediaType)
        ]

        if !prompt.isEmpty {
            contentBlocks.append(VisionContentBlock(text: prompt))
        }

        let visionMessage = VisionMessage(role: "user", content: contentBlocks)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let apiRequest = VisionAPIRequest(
            model: model,
            max_tokens: 4096,
            system: systemPrompt ?? Self.carbEstimationSystemPrompt,
            messages: [visionMessage]
        )

        request.httpBody = try JSONEncoder().encode(apiRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.apiError(errorResponse.error.message)
            }
            throw APIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        do {
            let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
            return apiResponse.textContent
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Prepare an image for the API by resizing and converting to base64
    /// - Parameter image: The original UIImage
    /// - Returns: A tuple of base64 string and media type, or nil if processing fails
    private func prepareImageForAPI(_ image: UIImage) -> (base64: String, mediaType: String)? {
        // Resize image to max 1568px on longest side (Claude's recommended max)
        let maxDimension: CGFloat = 1568
        let scale: CGFloat

        if image.size.width > image.size.height {
            scale = min(1.0, maxDimension / image.size.width)
        } else {
            scale = min(1.0, maxDimension / image.size.height)
        }

        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let finalImage = resizedImage else { return nil }

        // Try JPEG first (smaller file size), fall back to PNG
        if let jpegData = finalImage.jpegData(compressionQuality: 0.8) {
            return (jpegData.base64EncodedString(), "image/jpeg")
        } else if let pngData = finalImage.pngData() {
            return (pngData.base64EncodedString(), "image/png")
        }

        return nil
    }

    /// Estimate carbs from a food photo
    /// - Parameters:
    ///   - image: Photo of the food
    ///   - description: Optional description from the user (e.g., "small portion", "dressing on side")
    ///   - customPrompt: Custom instructions for the estimation
    ///   - defaultPortion: Default portion size assumption
    ///   - apiKey: Claude API key
    /// - Returns: The carb estimation response
    func estimateCarbs(
        from image: UIImage,
        description: String?,
        customPrompt: String,
        defaultPortion: String,
        apiKey: String
    ) async throws -> String {
        var promptParts: [String] = []

        // Add user description if provided
        if let description = description, !description.isEmpty {
            promptParts.append("User description: \(description)")
        }

        // Add portion size context
        promptParts.append("Default portion assumption: \(defaultPortion)")

        // Add the custom prompt (or default)
        promptParts.append(customPrompt)

        let fullPrompt = promptParts.joined(separator: "\n\n")

        return try await analyzeImage(
            image: image,
            prompt: fullPrompt,
            apiKey: apiKey,
            systemPrompt: Self.carbEstimationSystemPrompt
        )
    }
}
