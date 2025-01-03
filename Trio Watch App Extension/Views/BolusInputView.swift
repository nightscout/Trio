import Foundation
import SwiftUI
import WatchKit

// MARK: - Bolus Input View

struct BolusInputView: View {
    @Environment(\.dismiss) var dismiss
    @State private var bolusAmount = 0.0
    @State private var showingConfirmation = false
    @State private var confirmationProgress = 0.0
    let state: WatchState

    var body: some View {
        NavigationStack {
            if showingConfirmation {
                BolusConfirmationView(
                    bolusAmount: bolusAmount,
                    progress: $confirmationProgress,
                    state: state,
                    dismiss: dismiss
                )
                .navigationTitle("Confirm")
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if state.carbsAmount > 0 {
                                state.carbsAmount = 0
                            }
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .clipShape(Circle())
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Image(systemName: "digitalcrown.arrow.counterclockwise.fill")
                            .foregroundStyle(Color.white)
                    }
                }
            } else {
                VStack {
                    if state.carbsAmount > 0 {
                        HStack {
                            Text("Carbs: \(state.carbsAmount) g").font(.subheadline).padding(.bottom)
                            Spacer()
                        }
                    }

                    // TODO: handle bolus recommendation
                    Picker("Bolus", selection: $bolusAmount) {
                        ForEach(0 ... 100, id: \.self) { number in
                            Text(String(format: "%.1f U", Double(number) / 10))
                                .tag(Double(number) / 10)
                        }
                    }

                    Button("Add Bolus") {
                        showingConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                .navigationTitle("Add Insulin")
            }
        }
    }
}

struct BolusConfirmationView: View {
    let bolusAmount: Double
    @Binding var progress: Double
    let state: WatchState
    let dismiss: DismissAction

    @FocusState private var isCrownFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            if state.carbsAmount > 0 {
                Text(String(format: "%.1f g", state.carbsAmount))
                    .bold()
                    .foregroundStyle(.orange)
            }

            Text(String(format: "%.1f U", bolusAmount))
                .bold()
                .foregroundStyle(.blue)

            ProgressView(value: progress, total: 1.0)
                .tint(progress >= 1.0 ? .green : .blue)
                .padding(.horizontal)

            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
    }
}

#Preview {
    BolusInputView(state: WatchState())
}
