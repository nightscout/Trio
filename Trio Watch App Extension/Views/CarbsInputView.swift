import Foundation
import SwiftUI

// MARK: - Carbs Input View

struct CarbsInputView: View {
    @Binding var navigationPath: NavigationPath
    @State private var carbsAmount: Double = 0.0 // Needs to be Double due to .digitalCrownRotation() stride
    @FocusState private var isCrownFocused: Bool // Manage crown focus

    let state: WatchState
    let continueToBolus: Bool

    private var effectiveCarbsLimit: Double {
        Double(truncating: state.maxCarbs as NSNumber)
    }

    var trioBackgroundColor = LinearGradient(
        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        let buttonLabel = continueToBolus ? String(localized: "Proceed", comment: "Button Label to Proceed to Bolus on Watch") :
            String(localized: "Log Carbs", comment: "Button Label to Log Carbs on Watch")

        // TODO: introduce meal setting fpu enablement to conditional handle FPU
        VStack {
            Spacer()

            HStack {
                // "-" Button
                Button(action: {
                    if carbsAmount > 0 {
                        carbsAmount < 5 ? carbsAmount = 0 : (carbsAmount -= 5)
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .tint(.orange)
                }
                .buttonStyle(.borderless)
                .disabled(carbsAmount <= 0)

                Spacer()

                // Display the current carb amount
                Text(String(format: "%.0f \(String(localized: "g", comment: "gram of carbs"))", carbsAmount))
                    .fontWeight(.bold)
                    .font(.system(.title2, design: .rounded))
                    .foregroundColor(carbsAmount > 0.0 && carbsAmount >= effectiveCarbsLimit ? .loopRed : .primary)
                    .focusable(true)
                    .focused($isCrownFocused)
                    .digitalCrownRotation(
                        $carbsAmount,
                        from: 0,
                        through: effectiveCarbsLimit,
                        by: 1,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )

                Spacer()

                // "+" Button
                Button(action: {
                    carbsAmount = min(effectiveCarbsLimit, carbsAmount + 5)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .tint(.orange)
                }
                .buttonStyle(.borderless)
                .disabled(carbsAmount >= effectiveCarbsLimit)
            }.padding(.horizontal)

            Text("Carbohydrates")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom)

            Spacer()

            if carbsAmount > 0.0 && carbsAmount >= effectiveCarbsLimit {
                Text("Carbs Limit Reached!")
                    .font(.footnote)
                    .foregroundColor(.loopRed)
            }

            Button(buttonLabel) {
                if continueToBolus {
                    state.carbsAmount = Int(min(carbsAmount, effectiveCarbsLimit))
                    navigationPath.append(NavigationDestinations.bolusInput)
                } else {
                    state.sendCarbsRequest(Int(min(carbsAmount, effectiveCarbsLimit)))
                    navigationPath.append(NavigationDestinations.acknowledgmentPending)
                }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(!(carbsAmount > 0.0) || carbsAmount > effectiveCarbsLimit)
        }
        .background(trioBackgroundColor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "fork.knife")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
        }
    }
}
