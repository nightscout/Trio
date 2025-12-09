import Combine
import CoreData
import SwiftUI

extension AIInsightsConfig {
    enum Config {
        static let apiKeyKey = "AIInsightsConfig.claudeAPIKey"
    }

    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        let role: String
        let content: String
        let timestamp: Date

        var isUser: Bool { role == "user" }
    }

    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var keychain: Keychain!
        @Injected() private var storage: FileStorage!

        private let coredataContext = CoreDataStack.shared.newTaskContext()
        private let claudeService = ClaudeAPIService()

        // API Key
        @Published var apiKey = ""
        @Published var isAPIKeyConfigured = false
        @Published var isAPIKeyVisible = false

        // Quick Analysis
        @Published var quickAnalysisResult = ""
        @Published var isAnalyzing = false
        @Published var analysisError: String?

        // Chat
        @Published var chatMessages: [ChatMessage] = []
        @Published var currentMessage = ""
        @Published var isSendingMessage = false

        // Weekly Report
        @Published var weeklyReport = ""
        @Published var isGeneratingReport = false

        // Settings for context
        @Published var units: GlucoseUnits = .mgdL

        override func subscribe() {
            // Load API key from keychain
            if let storedKey = keychain.getValue(String.self, forKey: Config.apiKeyKey) {
                apiKey = storedKey
                isAPIKeyConfigured = !storedKey.isEmpty
            }

            // Get current units
            units = settingsManager.settings.units
        }

        // MARK: - API Key Management

        func saveAPIKey() {
            keychain.setValue(apiKey, forKey: Config.apiKeyKey)
            isAPIKeyConfigured = !apiKey.isEmpty
        }

        func deleteAPIKey() {
            keychain.removeObject(forKey: Config.apiKeyKey)
            apiKey = ""
            isAPIKeyConfigured = false
        }

        func toggleAPIKeyVisibility() {
            isAPIKeyVisible.toggle()
        }

        // MARK: - Data Export

        private func exportData() async throws -> HealthDataExporter.ExportedData {
            let exporter = HealthDataExporter(context: coredataContext)

            // Get current settings
            let settings = settingsManager.settings
            let preferences = settingsManager.preferences
            let pumpSettings = settingsManager.pumpSettings

            // Format carb ratios and ISF as strings
            let carbRatios = "Varies by time of day"
            let isfs = "Varies by time of day"

            let lowTarget = settings.units == .mgdL ? Int(settings.low) : Int(settings.low * 18)
            let highTarget = settings.units == .mgdL ? Int(settings.high) : Int(settings.high * 18)

            return try await exporter.exportLast7Days(
                units: settings.units.rawValue,
                targetLow: lowTarget,
                targetHigh: highTarget,
                maxIOB: preferences.maxIOB,
                maxBolus: pumpSettings.maxBolus,
                dia: pumpSettings.insulinActionCurve,
                carbRatios: carbRatios,
                isfs: isfs
            )
        }

        // MARK: - Quick Analysis

        @MainActor
        func runQuickAnalysis() async {
            guard isAPIKeyConfigured else {
                analysisError = "Please configure your Claude API key first."
                return
            }

            isAnalyzing = true
            analysisError = nil
            quickAnalysisResult = ""

            do {
                let data = try await exportData()
                let exporter = HealthDataExporter(context: coredataContext)
                let prompt = exporter.formatForPrompt(data, analysisType: .quick)

                let result = try await claudeService.analyze(prompt: prompt, apiKey: apiKey)
                quickAnalysisResult = result
            } catch {
                analysisError = error.localizedDescription
            }

            isAnalyzing = false
        }

        // MARK: - Chat

        @MainActor
        func sendChatMessage() async {
            guard isAPIKeyConfigured else {
                analysisError = "Please configure your Claude API key first."
                return
            }

            let userMessage = currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !userMessage.isEmpty else { return }

            // Add user message to chat
            chatMessages.append(ChatMessage(role: "user", content: userMessage, timestamp: Date()))
            currentMessage = ""
            isSendingMessage = true

            do {
                // Build messages array with context
                var apiMessages: [ClaudeAPIService.Message] = []

                // If this is the first message, include data context
                if chatMessages.count == 1 {
                    let data = try await exportData()
                    let exporter = HealthDataExporter(context: coredataContext)
                    let context = exporter.formatForPrompt(data, analysisType: .chat)
                    apiMessages.append(ClaudeAPIService.Message(role: "user", content: context))
                    apiMessages.append(ClaudeAPIService.Message(
                        role: "assistant",
                        content: "I've reviewed your 7-day glucose data. I can see your settings, statistics, and trends. What would you like to know?"
                    ))
                }

                // Add recent chat history (last 10 messages for context)
                let recentMessages = chatMessages.suffix(10)
                for msg in recentMessages {
                    apiMessages.append(ClaudeAPIService.Message(role: msg.role, content: msg.content))
                }

                let response = try await claudeService.sendMessage(messages: apiMessages, apiKey: apiKey)
                chatMessages.append(ChatMessage(role: "assistant", content: response, timestamp: Date()))
            } catch {
                chatMessages.append(ChatMessage(
                    role: "assistant",
                    content: "Sorry, I encountered an error: \(error.localizedDescription)",
                    timestamp: Date()
                ))
            }

            isSendingMessage = false
        }

        func clearChat() {
            chatMessages.removeAll()
        }

        // MARK: - Weekly Report

        @MainActor
        func generateWeeklyReport() async {
            guard isAPIKeyConfigured else {
                analysisError = "Please configure your Claude API key first."
                return
            }

            isGeneratingReport = true
            analysisError = nil
            weeklyReport = ""

            do {
                let data = try await exportData()
                let exporter = HealthDataExporter(context: coredataContext)
                let prompt = exporter.formatForPrompt(data, analysisType: .weeklyReport)

                let result = try await claudeService.analyze(prompt: prompt, apiKey: apiKey)
                weeklyReport = result
            } catch {
                analysisError = error.localizedDescription
            }

            isGeneratingReport = false
        }

        func getShareableReport() -> String {
            guard !weeklyReport.isEmpty else { return "" }

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long

            return """
            Trio AI Weekly Report
            Generated: \(dateFormatter.string(from: Date()))

            \(weeklyReport)

            ---
            This report was generated by AI for educational purposes.
            Always consult your healthcare provider before making treatment changes.
            """
        }
    }
}
