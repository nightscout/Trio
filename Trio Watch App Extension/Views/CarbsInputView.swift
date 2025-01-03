import Foundation
import SwiftUI

// MARK: - Carbs Input View

struct CarbsInputView: View {
    @Environment(\.dismiss) var dismiss
    @State private var carbsAmount = 0
    @State private var navigateToBolus = false // Track navigation to BolusInputView
    @FocusState private var isCrownFocused: Bool // Manage crown focus

    let state: WatchState
    let continueToBolus: Bool

    var body: some View {
        let buttonLabel = continueToBolus ? "Proceed" : "Add Carbs"

        // TODO: introduce meal setting fpu enablement to conditional handle FPU
        VStack {
            Picker("Carbs", selection: $carbsAmount) {
                ForEach(0 ... 100, id: \.self) { amount in
                    Text("\(amount) g").tag(amount)
                }
            }
            .focusable(true) // Enable focus for Digital Crown
            .focused($isCrownFocused) // Bind focus state
            .onAppear {
                isCrownFocused = true // Automatically focus when view appears
            }

            Button(buttonLabel) {
                if continueToBolus {
                    state.carbsAmount = carbsAmount
                    navigateToBolus = true
                } else {
                    state.sendCarbsRequest(carbsAmount)
                    dismiss()
                }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .navigationTitle("Add Carbs")
        .navigationDestination(isPresented: $navigateToBolus) {
            BolusInputView(state: state) // Navigate to BolusInputView
        }
    }
}
