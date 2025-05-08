import SwiftUI

extension Main {
    struct LoadingView: View {
        @Binding var showError: Bool
        let retry: () -> Void

        private let versionNumber = Bundle.main.releaseVersionNumber ?? String(localized: "Unknown")

        var body: some View {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack {
                    Spacer().frame(maxHeight: 92)

                    Image(.trioCircledNoBackground)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .shadow(color: Color.white.opacity(0.1), radius: 5, x: 0, y: 0)

                    Text("Trio v\(versionNumber)")
                        .fontWeight(.heavy)
                        .foregroundStyle(Color(red: 148 / 255, green: 102 / 255, blue: 234 / 255))
                        .padding(.vertical)

                    if showError {
                        Spacer().frame(maxHeight: 60)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Oops, there was an issue!").font(.title3).bold()

                            Text("Something went wrong while loading your data. Please try again in a few moments.")
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 24)
                        .foregroundStyle(.white)

                        Spacer()

                        RetryButton(action: retry).padding(.bottom, 60)
                    } else {
                        Spacer().frame(maxHeight: 100)

                        CustomProgressView(text: String(localized: "Getting everything ready for you...")).foregroundStyle(.white)

                        Spacer()
                    }
                }
            }
        }
    }

    struct RetryButton: View {
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .frame(width: UIScreen.main.bounds.width - 60, height: 50)
                .font(.title3).bold()
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
                .foregroundColor(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            }
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
