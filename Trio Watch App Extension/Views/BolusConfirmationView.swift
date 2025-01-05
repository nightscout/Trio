import Foundation
import SwiftUI
import WatchKit

struct BolusConfirmationView: View {
    @Binding var navigationPath: NavigationPath
    let state: WatchState
    @Binding var bolusAmount: Double
    @Binding var confirmationProgress: Double

    @FocusState private var isCrownFocused: Bool

    var trioBackgroundColor = LinearGradient(
        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        VStack(spacing: 10) {
            Spacer()

            VStack {
                if state.carbsAmount > 0 {
                    HStack {
                        Text("Carbs:")
                        Spacer()
                        Text("\(state.carbsAmount) g")
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

            ProgressView(value: confirmationProgress, total: 1.0)
                .tint(confirmationProgress >= 1.0 ? .green : .gray)
                .padding(.horizontal)

            Spacer()

            Button("Cancel") {
                if state.carbsAmount > 0 {
                    state.carbsAmount = 0 // reset carbs in state
                }
                bolusAmount = 0 // reset bolus in state
                confirmationProgress = 0 // reset auth progress
                navigationPath.removeLast(navigationPath.count)
            }
            .buttonStyle(.bordered)
        }
        .focusable(true)
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $confirmationProgress,
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
        .onChange(of: confirmationProgress) { _, newValue in
            if newValue >= 1.0 {
                WKInterfaceDevice.current().play(.success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if state.carbsAmount > 0 {
                        state.sendCarbsRequest(state.carbsAmount, Date())
                        state.carbsAmount = 0 // reset carbs in state
                    }
                    state.activeBolusAmount = bolusAmount
                    state.sendBolusRequest(Decimal(bolusAmount))
                    bolusAmount = 0 // reset bolus in state
                    confirmationProgress = 0 // reset auth progress
                    navigationPath.append(NavigationDestinations.acknowledgmentPending)
                }
            } else if newValue > 0 {
                WKInterfaceDevice.current().play(.click)
            }
        }
        .navigationTitle("Confirm")
        .background(trioBackgroundColor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "digitalcrown.arrow.counterclockwise.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white)
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
    }
}
