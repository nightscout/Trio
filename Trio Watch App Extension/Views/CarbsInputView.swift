import Foundation
import SwiftUI

// MARK: - Carbs Input View

struct CarbsInputView: View {
    @Binding var navigationPath: [NavigationDestinations]
    @State private var carbsAmount: Double = 0.0 // Needs to be Double due to .digitalCrownRotation() stride
    @FocusState private var isCrownFocused: Bool // Manage crown focus

    let state: WatchState
    let continueToBolus: Bool

    private var effectiveCarbsLimit: Double {
        // Extract current COB from string and convert to Double
        let currentCOB = Double(state.cob?.replacingOccurrences(of: " g", with: "") ?? "0") ?? 0

        // Calculate available COB
        let availableCOB = max(0, Double(truncating: state.maxCOB as NSNumber) - currentCOB)

        return min(
            Double(truncating: state.maxCarbs as NSNumber),
            availableCOB
        )
    }

    var trioBackgroundColor = LinearGradient(
        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        let buttonLabel = continueToBolus ? "Proceed" : "Log Carbs"

        // TODO: introduce meal setting fpu enablement to conditional handle FPU
        VStack {
            Spacer()

            HStack {
                // "-" Button
                Button(action: {
                    if carbsAmount > 0 { carbsAmount -= 1 }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.borderless)
                .disabled(carbsAmount < 1)

                Spacer()

                // Display the current carb amount
                Text(String(format: "%.0f g", carbsAmount))
                    .fontWeight(.bold)
                    .font(.system(.title2, design: .rounded))
                    .foregroundColor(carbsAmount > 0.0 && carbsAmount >= effectiveCarbsLimit ? .red : .primary)
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
                    carbsAmount += 1
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
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
                    .foregroundColor(.red)
            }

            Button(buttonLabel) {
                if continueToBolus {
                    state.carbsAmount = Int(min(carbsAmount, effectiveCarbsLimit))
                    navigationPath.append(NavigationDestinations.bolusInput)
                } else {
                    // TODO: add a fancy success animation
                    state.sendCarbsRequest(Int(min(carbsAmount, effectiveCarbsLimit)))
                    navigationPath.removeLast(navigationPath.count)
                }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(!(carbsAmount > 0.0) || carbsAmount >= effectiveCarbsLimit)
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
