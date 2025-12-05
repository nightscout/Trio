import Combine
import Foundation
import SwiftUI

extension BarcodeAi {
    /// Represents a Gemini model available for selection
    struct GeminiModel: Identifiable, Hashable {
        let id: String
        let displayName: String
        let description: String

        var name: String { id }
    }

    final class SettingsStateModel: BaseStateModel<Provider> {
        @Injected() private var keychain: Keychain!

        @Published var apiKey = ""
        @Published var message = ""
        @Published var hasApiKey = false

        // Model selection
        @Published var availableModels: [GeminiModel] = []
        @Published var selectedModelId: String = "gemini-2.0-flash"
        @Published var isLoadingModels = false

        // Default models in case API call fails
        private let defaultModels: [GeminiModel] = [
            GeminiModel(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash", description: "Fast and efficient"),
            GeminiModel(id: "gemini-1.5-flash", displayName: "Gemini 1.5 Flash", description: "Previous generation flash"),
            GeminiModel(id: "gemini-1.5-pro", displayName: "Gemini 1.5 Pro", description: "More capable, slower")
        ]

        override func subscribe() {
            // Load existing API key from keychain
            if let storedKey = keychain.getValue(String.self, forKey: Config.geminiApiKeyKey) {
                apiKey = storedKey
                hasApiKey = true
            } else {
                hasApiKey = false
            }

            // Load selected model from UserDefaults
            if let savedModelId = UserDefaults.standard.string(forKey: "geminiSelectedModel") {
                selectedModelId = savedModelId
            }

            // Set default models initially
            availableModels = defaultModels

            // Fetch available models if API key exists
            if hasApiKey {
                fetchAvailableModels()
            }
        }

        func fetchAvailableModels() {
            guard hasApiKey, !apiKey.isEmpty else {
                availableModels = defaultModels
                return
            }

            isLoadingModels = true

            Task {
                do {
                    let models = try await fetchModelsFromAPI()
                    await MainActor.run {
                        self.availableModels = models.isEmpty ? self.defaultModels : models
                        self.isLoadingModels = false

                        // If current selection is not in the list, reset to first available
                        if !self.availableModels.contains(where: { $0.id == self.selectedModelId }) {
                            self.selectedModelId = self.availableModels.first?.id ?? "gemini-2.0-flash"
                            self.saveSelectedModel()
                        }
                    }
                } catch {
                    await MainActor.run {
                        print("[BarcodeAI Settings] Failed to fetch models: \(error)")
                        self.availableModels = self.defaultModels
                        self.isLoadingModels = false
                    }
                }
            }
        }

        private func fetchModelsFromAPI() async throws -> [GeminiModel] {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100") else {
                throw NSError(domain: "BarcodeAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode
            else {
                throw NSError(domain: "BarcodeAI", code: -2, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArray = json["models"] as? [[String: Any]]
            else {
                throw NSError(domain: "BarcodeAI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            // Filter models that support generateContent and have vision capabilities
            let geminiModels = modelsArray.compactMap { modelData -> GeminiModel? in
                guard let name = modelData["name"] as? String,
                      let displayName = modelData["displayName"] as? String,
                      let supportedMethods = modelData["supportedGenerationMethods"] as? [String],
                      supportedMethods.contains("generateContent")
                else {
                    return nil
                }

                // Extract model ID from name (e.g., "models/gemini-2.0-flash" -> "gemini-2.0-flash")
                let modelId = name.replacingOccurrences(of: "models/", with: "")

                // Only include models that likely support vision (gemini models)
                guard modelId.contains("gemini") else {
                    return nil
                }

                let description = modelData["description"] as? String ?? ""

                return GeminiModel(
                    id: modelId,
                    displayName: displayName,
                    description: description
                )
            }

            // Sort by name, preferring newer versions
            return geminiModels.sorted { $0.displayName > $1.displayName }
        }

        func selectModel(_ modelId: String) {
            selectedModelId = modelId
            saveSelectedModel()
        }

        private func saveSelectedModel() {
            UserDefaults.standard.set(selectedModelId, forKey: "geminiSelectedModel")
        }

        func save() {
            guard !apiKey.isEmpty else {
                message = "Error: API key cannot be empty"
                return
            }

            keychain.setValue(apiKey, forKey: Config.geminiApiKeyKey)
            hasApiKey = true
            message = "API key saved successfully"

            // Fetch models after saving API key
            fetchAvailableModels()

            // Clear message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.message == "API key saved successfully" {
                    self.message = ""
                }
            }
        }

        func delete() {
            keychain.removeObject(forKey: Config.geminiApiKeyKey)
            apiKey = ""
            hasApiKey = false
            message = "API key removed"
            availableModels = defaultModels

            // Clear message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.message == "API key removed" {
                    self.message = ""
                }
            }
        }
    }
}
