import Foundation
import SwiftUI
import WatchKit

// MARK: - Bolus Input View

struct BolusInputView: View {
    @State private var bolusAmount = 0.0
    @State private var navigateToConfirmation = false
    @State private var confirmationProgress = 0.0

    let state: WatchState

    @FocusState private var isCrownFocused: Bool

    var body: some View {
        VStack {
            if state.carbsAmount > 0 {
                HStack {
                    Text("Carbs:").bold().font(.subheadline).padding(.leading)
                    Text("\(state.carbsAmount) g").font(.subheadline).foregroundStyle(Color.orange)
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
                navigateToConfirmation = true
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
        .navigationDestination(isPresented: $navigateToConfirmation) {
            BolusConfirmationView(
                bolusAmount: bolusAmount,
                progress: $confirmationProgress,
                state: state
            )
        }
    }
}

#Preview {
    BolusInputView(state: WatchState())
}
