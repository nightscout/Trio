import SwiftUI
import Swinject

extension MealScan {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.dismiss) var dismiss

        var onConfirm: ((NutritionTotals) -> Void)?

        var body: some View {
            NavigationStack {
                Group {
                    switch state.phase {
                    case .camera:
                        CameraCaptureView(
                            onImageCaptured: { image in
                                state.capturePhoto(image)
                            },
                            onCancel: {
                                dismiss()
                            }
                        )

                    case .analyzing:
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Analyzing your meal...")
                                .font(.headline)
                            Text("Identifying foods and estimating nutrition")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                    case .chat:
                        MealChatView(state: state)

                    case .confirming:
                        Color.clear
                            .onAppear {
                                dismiss()
                            }
                    }
                }
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if state.phase != .camera {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                state.cancel()
                                dismiss()
                            }
                        }
                    }
                }
                .alert("Error", isPresented: $state.showError) {
                    Button("OK") { state.showError = false }
                } message: {
                    Text(state.errorMessage ?? "An unexpected error occurred")
                }
            }
            .onAppear {
                configureView()
                state.onConfirm = { totals in
                    onConfirm?(totals)
                }
            }
        }

        private var navigationTitle: String {
            switch state.phase {
            case .camera: return "Scan Meal"
            case .analyzing: return "Analyzing..."
            case .chat: return "Meal Review"
            case .confirming: return ""
            }
        }
    }
}
