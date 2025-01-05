import Foundation
import SwiftUI
import WatchKit

// MARK: - Bolus Input View

struct BolusInputView: View {
    @Binding var navigationPath: NavigationPath
    @State private var bolusAmount = 0.0

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

    var trioBackgroundColor = LinearGradient(
        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        VStack {
            if effectiveBolusLimit == 0 {
                VStack(spacing: 10) {
                    Spacer()

                    Text("Bolus limit cannot be fetched from phone!").font(.headline)
                    Text("Check device settings, connect to phone, and try again.").font(.caption)

                    Spacer()
                }
                .foregroundColor(.red)
                .scenePadding()
            } else {
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
                        .foregroundColor(bolusAmount > 0.0 && bolusAmount >= effectiveBolusLimit ? .red : .primary)
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

                if bolusAmount > 0.0 && bolusAmount >= effectiveBolusLimit {
                    Text("Bolus Limit Reached!")
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                Button("Log Bolus") {
                    state.bolusAmount = min(bolusAmount, effectiveBolusLimit)
//                    navigationState.path.append(NavigationDestinations.bolusConfirm)
                    navigationPath.append(NavigationDestinations.bolusConfirm)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(!(bolusAmount > 0.0) || bolusAmount >= effectiveBolusLimit)
            }
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
        .blur(radius: state.showBolusProgressOverlay ? 3 : 0)
        .overlay {
            if state.showBolusProgressOverlay {
                BolusProgressOverlay(state: state)
                    .transition(.opacity)
            }
        }
    }
}
