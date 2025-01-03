import Foundation
import SwiftUI

// MARK: - Carbs Input View

struct CarbsInputView: View {
    @Environment(\.dismiss) var dismiss
    @State private var carbsAmount = 0
    @State private var navigateToBolus = false // Track navigation to BolusInputView

    let state: WatchState
    let continueToBolus: Bool

    var body: some View {
        let buttonLabel = continueToBolus ? "Continue to Bolus" : "Add Carbs"

        // TODO: introduce meal setting fpu enablement to conditional handle FPU
        NavigationStack {
            VStack {
                Picker("Carbs", selection: $carbsAmount) {
                    ForEach(0 ... 100, id: \.self) { amount in
                        Text("\(amount)g").tag(amount)
                    }
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
}
