import SwiftUI

struct AcknowledgementPendingView: View {
    @Binding var navigationPath: [NavigationDestinations]
    let state: WatchState

    var trioBackgroundColor = LinearGradient(
        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
        startPoint: .top,
        endPoint: .bottom
    )

    var statusIcon: some View {
        switch state.acknowledgementStatus {
        case .pending:
            return Image(systemName: "progress.indicator").foregroundStyle(Color.secondary)
        case .success:
            return Image(systemName: "checkmark.circle").foregroundStyle(Color.green)
        case .failure:
            return Image(systemName: "progress.indicator").foregroundStyle(Color.red)
        }
    }

    var body: some View {
        Group {
            VStack {
                if state.isMealBolusCombo {
                    ProgressView()
                    Text(state.mealBolusStep.rawValue).multilineTextAlignment(.center)
                } else if state.showCommsAnimation {
                    ProgressView()
                    Text("Processing…")
                } else if state.showAcknowledgmentBanner {
                    statusIcon.padding()
                    Text(state.acknowledgmentMessage).multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
        .background(trioBackgroundColor)
        .onChange(of: state.showAcknowledgmentBanner) { _, newValue in
            if !newValue {
                // Navigate back to the root when acknowledgment banner disappears
                navigationPath.removeAll()
            }
        }
    }
}
