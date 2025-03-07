import SwiftUI

extension Main {
    struct LoadingView: View {
        @Binding var showError: Bool
        let retry: () -> Void
        var body: some View {
            VStack {
                Spacer().frame(maxHeight: 92)
                Image(.trioWhite)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                Spacer().frame(maxHeight: 32)
                ZStack {
                    // Invisible placeholder with same height as progress view
                    Color.clear.frame(width: 30, height: 30)
                    ProgressView()
                        .scaleEffect(1.5)
                        .opacity(showError ? 0 : 1)
                }
                Spacer().frame(maxHeight: 32)
                if showError {
                    Text("Something went wrong while loading your data. Please try again in a few moments.")
                    Spacer().frame(maxHeight: 32)
                    RetryButton(action: retry)
                } else {
                    Text("Getting everything ready for you...")
                }
                Spacer()
            }
            .padding()
        }
    }

    struct RetryButton: View {
        var action: () -> Void
        var label: String = "Retry"
        var iconName: String = "arrow.clockwise"

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .medium))
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            }
            // .buttonStyle(ScaleButtonStyle())
        }
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Main.LoadingView(showError: .constant(false), retry: {})
                .previewDisplayName("Loading")
            Main.LoadingView(showError: .constant(true), retry: {})
                .previewDisplayName("Error")
        }
    }
}
