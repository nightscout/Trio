import Foundation
import SwiftUI
import WatchKit

// MARK: - Bolus Input View

struct BolusInputView: View {
    @ObservedObject var navigationState: NavigationState
    @State private var bolusAmount = 0.0
    @State private var navigateToConfirmation = false

    let state: WatchState

    @FocusState private var isCrownFocused: Bool

    private var effectiveBolusLimit: Double {
        // Extract current IOB from string and convert to Double
        let currentIOB = Double(state.iob?.replacingOccurrences(of: " U", with: "") ?? "0") ?? 0

        // Calculate available IOB
        let availableIOB = max(0, Double(truncating: state.maxIOB as NSNumber) - currentIOB)

        return min(
            Double(truncating: state.maxBolus as NSNumber),
            availableIOB
        )
    }

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
                        through: effectiveBolusLimit,
                        by: 1, // TODO: use pump increment here
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )

                Spacer()

                // "+" Button
                Button(action: {
                    bolusAmount += 0.5
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .disabled(bolusAmount >= effectiveBolusLimit)
            }.padding(.horizontal)

            Text("Insulin")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom)

            Spacer()

            Button("Log Bolus") {
                state.bolusAmount = min(bolusAmount, effectiveBolusLimit)
                navigationState.path.append(NavigationDestinations.bolusConfirm)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(!(bolusAmount > 0.0) || bolusAmount >= effectiveBolusLimit)
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

#Preview {
    BolusInputView(navigationState: NavigationState(), state: WatchState())
}
