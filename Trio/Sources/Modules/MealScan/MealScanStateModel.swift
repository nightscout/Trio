import Combine
import Foundation
import Observation
import SwiftUI
import Swinject
import UIKit

extension MealScan {
    @Observable final class StateModel: BaseStateModel<MealScanProvider> {
        var capturedImage: UIImage?
        var phase: MealScanPhase = .camera
        var detectedFoods: [DetectedFood] = []
        var chatMessages: [ChatMessage] = []
        var currentStreamingText: String = ""
        var userInput: String = ""
        var isStreaming: Bool = false
        var errorMessage: String?
        var showError: Bool = false

        var runningTotals: NutritionTotals = .zero

        var onConfirm: ((NutritionTotals) -> Void)?

        // MARK: - Camera

        func capturePhoto(_ image: UIImage) {
            capturedImage = image
            phase = .analyzing
            Task {
                await analyzeImage()
            }
        }

        // MARK: - Analysis

        @MainActor
        private func analyzeImage() async {
            guard let image = capturedImage else { return }

            do {
                let eatenFoodIds = provider.fetchStoredFoodIds()
                let foods = try await provider.recognizeImage(image, eatenFoodIds: eatenFoodIds)

                detectedFoods = foods
                runningTotals = NutritionTotals.from(foods)
                phase = .chat

                // Start Claude session for review
                await startClaudeSession()

            } catch {
                errorMessage = error.localizedDescription
                showError = true
                phase = .camera
            }
        }

        @MainActor
        private func startClaudeSession() async {
            guard let image = capturedImage else { return }

            do {
                isStreaming = true
                let customNotes = provider.fetchCustomFoodNotes()
                let stream = try await provider.startChatSession(image: image, detectedFoods: detectedFoods, customFoodNotes: customNotes)

                var assistantText = ""
                var message = ChatMessage(role: .assistant, text: "")
                chatMessages.append(message)
                let messageIndex = chatMessages.count - 1

                for await chunk in stream {
                    assistantText += chunk
                    chatMessages[messageIndex].text = assistantText
                }

                // Parse totals from Claude's response
                if let totals = BaseClaudeNutritionService.parseTotals(from: assistantText) {
                    chatMessages[messageIndex].updatedTotals = totals
                    runningTotals = totals
                }

                isStreaming = false

            } catch {
                isStreaming = false
                // Claude failure is non-fatal — user can still use FatSecret results
                let errorMsg = ChatMessage(
                    role: .assistant,
                    text: "I wasn't able to connect for a detailed review. You can still use the scan results above, or type corrections below."
                )
                chatMessages.append(errorMsg)
            }
        }

        // MARK: - Chat

        @MainActor
        func sendMessage() async {
            let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isStreaming else { return }

            let userMessage = ChatMessage(role: .user, text: text)
            chatMessages.append(userMessage)
            userInput = ""

            do {
                isStreaming = true
                let stream = try await provider.sendChatMessage(text)

                var assistantText = ""
                var message = ChatMessage(role: .assistant, text: "")
                chatMessages.append(message)
                let messageIndex = chatMessages.count - 1

                for await chunk in stream {
                    assistantText += chunk
                    chatMessages[messageIndex].text = assistantText
                }

                if let totals = BaseClaudeNutritionService.parseTotals(from: assistantText) {
                    chatMessages[messageIndex].updatedTotals = totals
                    runningTotals = totals
                }

                isStreaming = false

            } catch {
                isStreaming = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }

        // MARK: - Food List Editing

        func removeFood(at index: Int) {
            guard detectedFoods.indices.contains(index) else { return }
            detectedFoods[index].isRemoved = true
            runningTotals = NutritionTotals.from(detectedFoods)
        }

        func restoreFood(at index: Int) {
            guard detectedFoods.indices.contains(index) else { return }
            detectedFoods[index].isRemoved = false
            runningTotals = NutritionTotals.from(detectedFoods)
        }

        // MARK: - Confirm

        func confirm() {
            provider.storeFoodIds(from: detectedFoods)
            onConfirm?(runningTotals)
            phase = .confirming
        }

        func cancel() {
            provider.resetChat()
            capturedImage = nil
        }
    }
}
