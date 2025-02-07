import SwiftUI

struct BolusProgressOverlay: View {
    let state: WatchState
    let onCancelBolus: () -> Void

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
        VStack(spacing: 10) {
            VStack {
                Text("Bolusing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top)

                ProgressView(value: state.bolusProgress, total: 1.0)
                    .tint(progressGradient)

                Text(String(
                    format: "%.2f U of %.2f U",
                    state.deliveredAmount,
                    state.activeBolusAmount
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: {
                    state.sendCancelBolusRequest()
                    onCancelBolus()
                }) {
                    Text("Cancel Bolus")
                }
                .buttonStyle(.bordered)
                .padding()
            }
            .padding()
            .background(Color.black.opacity(0.9))
            .cornerRadius(10)
        }
        .scenePadding()
        .onChange(of: state.bolusProgress) { _, newProgress in
            if newProgress >= 1.0 {
                state.activeBolusAmount = 0 // Reset only when bolus is complete
            }
        }
        .onDisappear {
            state.activeBolusAmount = 0 // Triple-check to reset when view disappears
        }
    }
}
