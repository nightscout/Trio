import SwiftUI

struct AcknowledgementPendingView: View {
    @Binding var navigationPath: NavigationPath
    let state: WatchState
    @Binding var shouldNavigateToRoot: Bool

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
            return Image(systemName: "checkmark.circle").foregroundStyle(Color.loopGreen)
        case .failure:
            return Image(systemName: "xmark").foregroundStyle(Color.loopRed)
        }
    }

    var body: some View {
        Group {
            VStack {
                if state.isMealBolusCombo {
                    ProgressView()
                    Text(state.mealBolusStep.rawValue).multilineTextAlignment(.center)
                } else if state.showAcknowledgmentBanner {
                    statusIcon.padding()
                    Text(state.acknowledgmentMessage).multilineTextAlignment(.center)
                        .foregroundStyle(state.acknowledgementStatus == .failure ? Color.loopRed : Color.primary)
                } else if state.showCommsAnimation {
                    ProgressView()
                    Text("Processing…")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
        .background(trioBackgroundColor)
        // WatchState times out a missing answer by showing a banner (beginAwaitingAcknowledgment), so every
        // request ends here. A timer in this view never started: the flag is already true when the view appears.
        .onChange(of: state.showAcknowledgmentBanner) { _, newValue in
            if !newValue {
                // Navigate back to the root when acknowledgment banner disappears
                navigationPath.removeLast(navigationPath.count)
            }
        }
        .onDisappear {
            state.shouldNavigateToRoot = true
        }
    }
}
