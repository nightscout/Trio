import Combine
import Foundation

/// Service for communicating with the Claude API
final class ClaudeAPIService {
    enum APIError: LocalizedError {
        case noAPIKey
        case invalidURL
        case networkError(Error)
        case invalidResponse
        case apiError(String)
        case decodingError(Error)

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
            }
        }
    }

    struct Message: Codable {
        let role: String
        let content: String
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
}
