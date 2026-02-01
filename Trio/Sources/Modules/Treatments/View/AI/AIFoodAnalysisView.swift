import SwiftUI

/// Self-contained view for AI-assisted food analysis.
/// Manages its own state for photo capture, description input, analysis, and item selection.
/// Communicates results back via the `onApplyCarbs` callback.
struct AIFoodAnalysisView: View {
    @Bindable var state: Treatments.StateModel
    let onOpenChat: () -> Void

    @State private var showPhotoSourcePicker = false
    @State private var showPhotoPicker = false
    @State private var photoSourceType: PhotoSourceType = .photoLibrary
    @State private var selectedImage: UIImage?
    @State private var isFoodItemsExpanded = false

    var body: some View {
        Group {
            if !state.isInAIMode {
                // AI button
                AnimatedRainbowButton(
                    title: NSLocalizedString("Analyze Food with AI", comment: "Button label for AI-assisted food analysis"),
                    icon: "sparkles",
                    isLoading: state.isAnalyzingFood,
                    action: { showPhotoSourcePicker = true }
                )
                .padding(.bottom, 4)
            } else if let imageData = state.capturedImageData,
                      state.foodItemSelection == nil || state.isAnalyzingFood
            {
                // Description input + analyzing overlay
                ZStack {
                    FoodDescriptionInputView(
                        description: Binding(
                            get: { state.foodDescription },
                            set: { state.foodDescription = $0 }
                        ),
                        imageData: imageData,
                        onAnalyze: {
                            state.isAnalyzingFood = true
                            Task {
                                await state.analyzeFood(
                                    imageData: imageData,
                                    description: state.foodDescription.isEmpty ? nil : state.foodDescription
                                )
                            }
                        },
                        onCancel: {
                            guard !state.isAnalyzingFood else { return }
                            withAnimation(.easeInOut(duration: 0.35)) {
                                state.capturedImageData = nil
                                state.foodDescription = ""
                            }
                        }
                    )
                    .disabled(state.isAnalyzingFood)
                    .opacity(state.isAnalyzingFood ? 0.4 : 1.0)

                    if state.isAnalyzingFood {
                        analysisOverlay
                    }
                }
            } else if state.foodItemSelection != nil {
                // Food items selection tree
                FoodItemsSelectionView(
                    selection: $state.foodItemSelection,
                    isExpanded: $isFoodItemsExpanded,
                    pendingItemIds: state.pendingItemIds,
                    onToggleItem: { itemId in
                        state.toggleFoodItem(itemId)
                    },
                    onEditItem: { itemId, newDescription in
                        Task {
                            await state.editFoodItemDescription(itemId, newDescription: newDescription)
                        }
                    },
                    onOpenChat: onOpenChat
                )
                .transition(.opacity)
            }
        }
        .actionSheet(isPresented: $showPhotoSourcePicker) {
            ActionSheet(
                title: Text("Select Photo Source"),
                buttons: [
                    .default(Text("Camera")) {
                        photoSourceType = .camera
                        showPhotoPicker = true
                    },
                    .default(Text("Photo Library")) {
                        photoSourceType = .photoLibrary
                        showPhotoPicker = true
                    },
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerWrapper(
                selectedImage: $selectedImage,
                isPresented: $showPhotoPicker,
                sourceType: photoSourceType
            )
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage,
               let imageData = image.compressedForAI()
            {
                withAnimation(.easeInOut(duration: 0.35)) {
                    state.capturedImageData = imageData
                    state.foodDescription = ""
                }
                selectedImage = nil
            }
        }
        .alert(
            Text("AI Analysis Error"),
            isPresented: Binding(
                get: { state.aiError != nil },
                set: { if !$0 { state.clearAIError() } }
            ),
            actions: {
                Button("OK") {
                    state.clearAIError()
                }
            },
            message: {
                Text(state.aiError ?? "")
            }
        )
    }

    private var analysisOverlay: some View {
        VStack(spacing: 8) {
            AnimatedSparkleIcon(isAnimating: true)
                .scaleEffect(1.5)

            Text("Analyzing\u{2026}")
                .font(.caption.bold())
                .foregroundColor(Color(hue: 0.75, saturation: 0.6, brightness: 0.8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.clear)
                .totalShimmer(isAnimating: true)
        )
    }
}
