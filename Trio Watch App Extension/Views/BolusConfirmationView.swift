import Foundation
import SwiftUI
import WatchKit

struct BolusConfirmationView: View {
    @Environment(\.dismiss) var dismiss

    let bolusAmount: Double
    @Binding var progress: Double
    let state: WatchState

    @FocusState private var isCrownFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Spacer()

            VStack {
                if state.carbsAmount > 0 {
                    HStack {
                        Text("Carbs:")
                        Spacer()
                        Text(String(format: "%.1f g", state.carbsAmount))
                            .bold()
                            .foregroundStyle(.orange)
                    }.padding(.horizontal)
                }

                HStack {
                    Text("Bolus")
                    Spacer()
                    Text(String(format: "%.1f U", bolusAmount))
                        .bold()
                        .foregroundStyle(.blue)
                }.padding(.horizontal)
            }

            ProgressView(value: progress, total: 1.0)
                .tint(progress >= 1.0 ? .green : .gray)
                .padding(.horizontal)

            Spacer()

            Button("Cancel") {
                if state.carbsAmount > 0 {
                    state.carbsAmount = 0 // reset carbs in state
                }
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(!(bolusAmount > 0.0))
        }
        .focusable(true)
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $progress,
            from: 0.0,
            through: 1.0,
            by: 0.05,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            isCrownFocused = true
        }
        .onChange(of: progress) { _, newValue in
            if newValue >= 1.0 {
                WKInterfaceDevice.current().play(.success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if state.carbsAmount > 0 {
                        state.sendCarbsRequest(state.carbsAmount, Date())
                        state.carbsAmount = 0 // reset carbs in state
                    }
                    state.sendBolusRequest(Decimal(bolusAmount))
                    dismiss()
                }
            } else if newValue > 0 {
                WKInterfaceDevice.current().play(.click)
            }
        }
        .navigationTitle("Confirm")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "digitalcrown.arrow.counterclockwise.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white)
            }
        }
    }
}
