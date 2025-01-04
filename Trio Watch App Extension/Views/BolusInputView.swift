import Foundation
import SwiftUI
import WatchKit

// MARK: - Bolus Input View

struct BolusInputView: View {
    @ObservedObject var navigationState: NavigationState
    @State private var bolusAmount = 0.0

    let state: WatchState

    @FocusState private var isCrownFocused: Bool

    var trioBackgroundColor = LinearGradient(
        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
        startPoint: .top,
        endPoint: .bottom
    )

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
                    bolusAmount += 0.5
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
                state.bolusAmount = bolusAmount
                navigationState.path.append(NavigationDestinations.bolusConfirm)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(!(bolusAmount > 0.0))
        }
        .background(trioBackgroundColor)
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
        .blur(radius: state.bolusProgress > 0 && state.bolusProgress < 1.0 && !state.isBolusCanceled ? 3 : 0)
        .overlay {
            if state.bolusProgress > 0 && state.bolusProgress < 1.0 && !state.isBolusCanceled {
                BolusProgressOverlay(state: state)
                    .transition(.opacity)
            }
        }
    }
}

#Preview {
    BolusInputView(navigationState: NavigationState(), state: WatchState())
}
