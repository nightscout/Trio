import Foundation
import SwiftUI
import WatchKit

// MARK: - Bolus Input View

struct BolusInputView: View {
    @Environment(\.dismiss) var dismiss
    @State private var bolusAmount = 0.0
    @State private var isExternalInsulin = false
    @State private var showingConfirmation = false
    @State private var confirmationProgress = 0.0
    let state: WatchState

    var body: some View {
        NavigationView {
            if showingConfirmation {
                BolusConfirmationView(
                    amount: bolusAmount,
                    isExternal: isExternalInsulin,
                    progress: $confirmationProgress,
                    state: state,
                    dismiss: dismiss
                )
            } else {
                VStack {
                    Picker("Bolus", selection: $bolusAmount) {
                        ForEach(0 ... 100, id: \.self) { number in
                            Text(String(format: "%.1f U", Double(number) / 10))
                                .tag(Double(number) / 10)
                        }
                    }

                    Toggle("External Insulin", isOn: $isExternalInsulin)
                        .toggleStyle(.switch)
                        .padding(.horizontal)

                    Button(isExternalInsulin ? "Add External Insulin" : "Add Bolus") {
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
    let amount: Double
    let isExternal: Bool
    @Binding var progress: Double
    let state: WatchState
    let dismiss: DismissAction

    @FocusState private var isCrownFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text("Confirm \(isExternal ? "External Insulin" : "Bolus")")
                .font(.headline)

            Text(String(format: "%.1f U", amount))
                .font(.title2)
                .bold()

            Text("Scroll crown down\nto confirm")
                .multilineTextAlignment(.center)
                .font(.caption2)
                .foregroundStyle(.secondary)

            ProgressView(value: progress, total: 1.0)
                .tint(progress >= 1.0 ? .green : .blue)
                .padding(.horizontal)

            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .navigationBarBackButtonHidden(true)
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
                    state.sendBolusRequest(Decimal(amount), isExternal: isExternal)
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
