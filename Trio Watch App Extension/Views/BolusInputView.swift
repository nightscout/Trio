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

    @FocusState private var isCrownFocused: Bool

    var body: some View {
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
                            state.carbsAmount = 0 // reset carbs in state
                        }
                        showingConfirmation.toggle()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "digitalcrown.arrow.counterclockwise.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.white)
                }
            }
        } else {
            VStack {
                if state.carbsAmount > 0 {
                    HStack {
                        Text("Carbs:").bold().font(.subheadline).padding(.leading)
                        Text(String(format: "%.0f g", state.carbsAmount)).font(.subheadline).foregroundStyle(Color.orange)
                        Spacer()
                    }
                }

                Spacer()

                HStack {
                    // "-" Button
                    Button(action: {
                        if bolusAmount > 0 { bolusAmount -= 1 }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    .disabled(bolusAmount < 1)

                    Spacer()

                    // Display the current carb amount
                    Text(String(format: "%.2f U", bolusAmount))
                        .fontWeight(.bold)
                        .font(.system(.title2, design: .rounded))
                        .foregroundColor(.primary)
                        .focusable(true)
                        .focused($isCrownFocused)
                        .digitalCrownRotation(
                            $bolusAmount,
                            from: 0,
                            through: 150.0, // TODO: use maxBolus here
                            by: 1, // TODO: use pump increment here
                            sensitivity: .medium,
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )

                    Spacer()

                    // TODO: introduce maxBolus here, disable button if bolusAmount > maxBolus
                    // "+" Button
                    Button(action: {
                        bolusAmount += 1
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                }.padding(.horizontal)

                Text("Insulin")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom)

                Spacer()

                Button("Log Bolus") {
                    showingConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(!(bolusAmount > 0.0))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "syringe.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
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

            ProgressView(value: progress, total: 1.0)
                .tint(progress >= 1.0 ? .green : .gray)
                .padding(.horizontal)
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
