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
            if state.showBolusCalculationProgress {
                ProgressView("Calculating Bolus...")
                Spacer()
            } else {
                if effectiveBolusLimit == 0 {
                    VStack(spacing: 8) {
                        Text("Bolus limit cannot be fetched from phone!").font(.headline)
                        Text("Check device settings, connect to phone, and try again.").font(.caption)
                    }
                    .scenePadding()
                } else {
                    if state.carbsAmount > 0 {
                        // Display the current carb amount
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
                            if bolusAmount > 0 { bolusAmount -= Double(truncating: state.bolusIncrement as NSNumber) }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundColor(Color.insulin)
                        }
                        .buttonStyle(.borderless)
                        .disabled(bolusAmount == 0)

                        Spacer()

                        let bolusIncrement = Double(truncating: state.bolusIncrement as NSNumber)
                        let adjustedBolusAmount = floor(bolusAmount / bolusIncrement) * bolusIncrement

                        Text(String(format: "%.2f U", adjustedBolusAmount))
                            .fontWeight(.bold)
                            .font(.system(.title2, design: .rounded))
                            .foregroundColor(bolusAmount > 0.0 && bolusAmount >= effectiveBolusLimit ? .loopRed : .primary)
                            .focusable(true)
                            .focused($isCrownFocused)
                            .digitalCrownRotation(
                                $bolusAmount,
                                from: 0,
                                through: effectiveBolusLimit,
                                by: Double(truncating: state.bolusIncrement as NSNumber),
                                sensitivity: .medium,
                                isContinuous: false,
                                isHapticFeedbackEnabled: true
                            )

                        Spacer()

                        // "+" Button
                        Button(action: {
                            bolusAmount += Double(truncating: state.bolusIncrement as NSNumber)
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(Color.insulin)
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
                            .foregroundColor(.loopRed)
                    }

                    Button("Log Bolus") {
                        state.bolusAmount = min(bolusAmount, effectiveBolusLimit)
                        navigationPath.append(NavigationDestinations.bolusConfirm)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.insulin)
                    .disabled(!(bolusAmount > 0.0) || bolusAmount >= effectiveBolusLimit)

                    Text(String(format: "Recommended: %.1f U", NSDecimalNumber(decimal: state.recommendedBolus).doubleValue))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                    .background(Color.insulin)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
        }
        .blur(radius: state.showBolusProgressOverlay ? 3 : 0)
        .overlay {
            if state.showBolusProgressOverlay {
                BolusProgressOverlay(state: state) {
                    state.shouldNavigateToRoot = false
                    navigationPath.append(NavigationDestinations.acknowledgmentPending)
                }.transition(.opacity)
            }
        }
        .onAppear {
            // Set initial bolus amount to recommended value
            // Only do this if user has not updated amount previously, e.g., when navigating to next and then back to this view
            if bolusAmount == 0 {
                state.requestBolusRecommendation()
                bolusAmount = Double(truncating: NSDecimalNumber(decimal: state.recommendedBolus))
            }
        }
        // Add onChange to update bolus amount when recommendation changes
        .onChange(of: state.recommendedBolus) { _, newValue in
            if bolusAmount == 0 { // Only update if user hasn't modified the value
                bolusAmount = Double(truncating: NSDecimalNumber(decimal: newValue))
            }
        }
    }
}
