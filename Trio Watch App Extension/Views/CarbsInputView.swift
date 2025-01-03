import Foundation
import SwiftUI

// MARK: - Carbs Input View

struct CarbsInputView: View {
    @Environment(\.dismiss) var dismiss
    @State private var carbsAmount: Double = 0.0 // Needs to be Double due to .digitalCrownRotation() stride
    @State private var navigateToBolus = false // Track navigation to BolusInputView
    @FocusState private var isCrownFocused: Bool // Manage crown focus

    let state: WatchState
    let continueToBolus: Bool

    var body: some View {
        let buttonLabel = continueToBolus ? "Proceed" : "Log Carbs"

        // TODO: introduce meal setting fpu enablement to conditional handle FPU
        VStack {
            Spacer()

            HStack {
                // "-" Button
                Button(action: {
                    if carbsAmount > 0 { carbsAmount -= 1 }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.borderless)
                .disabled(carbsAmount < 1)

                Spacer()

                // Display the current carb amount
                Text(String(format: "%.0f g", carbsAmount))
                    .fontWeight(.bold)
                    .font(.system(.title2, design: .rounded))
                    .foregroundColor(.primary)
                    .focusable(true)
                    .focused($isCrownFocused)
                    .digitalCrownRotation(
                        $carbsAmount,
                        from: 0,
                        through: 150.0, // TODO: introduce maxCarbs here
                        by: 1,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )

                Spacer()

                // TODO: introduce maxCarbs here, disable button if carbsAmount > maxCarbs
                // "+" Button
                Button(action: {
                    carbsAmount += 1
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.borderless)
            }.padding(.horizontal)

            Text("Carbohydrates")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom)

            Spacer()

            Button(buttonLabel) {
                if continueToBolus {
                    state.carbsAmount = Int(carbsAmount)
                    navigateToBolus = true
                } else {
                    state.sendCarbsRequest(Int(carbsAmount))
                    dismiss()
                }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(!(carbsAmount > 0.0))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "fork.knife")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
        }
        .navigationDestination(isPresented: $navigateToBolus) {
            BolusInputView(state: state) // Navigate to BolusInputView
        }
    }
}
