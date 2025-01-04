import SwiftUI

struct BolusProgressOverlay: View {
    let state: WatchState
    @ObservedObject var navigationState: NavigationState

    private let progressGradient = LinearGradient(
        colors: [
            Color(red: 0.7215686275, green: 0.3411764706, blue: 1), // #B857FF
            Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569), // #9F6CFA
            Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765), // #7C8BF3
            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961), // #57AAEC
            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902) // #43BBE9
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        if state.bolusProgress > 0 && state.bolusProgress < 1.0 {
            VStack {
                Spacer()
                VStack(spacing: 4) {
                    HStack {
                        ProgressView(value: state.bolusProgress, total: 1.0)
                            .tint(progressGradient)

                        Button(action: {
                            state.sendCancelBolusRequest()
                            navigationState.resetToRoot()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(String(
                        format: "%.1f U of %.1f U",
                        state.bolusProgress * state.activeBolusAmount,
                        state.activeBolusAmount
                    ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding()
            }
        }
    }
}
