import SwiftUI
import Swinject

extension Bolus {
    struct RootView: View {
        let resolver: Resolver
        let waitForSuggestion: Bool
        let fetch: Bool
        @StateObject var state = StateModel()

        var body: some View {
            if state.useCalc {
                // show alternative bolus calc based on toggle in bolus calc settings
                AlternativeBolusCalcRootView(
                    resolver: resolver,
                    state: state
                )
            } else {
                // show iAPS standard bolus calc
                DefaultBolusCalcRootView(
                    resolver: resolver,
                    waitForSuggestion: waitForSuggestion,
                    fetch: fetch,
                    state: state
                )
            }
        }
    }
}

// fix iOS 15 bug
struct ActivityIndicator: UIViewRepresentable {
    @Binding var isAnimating: Bool
    let style: UIActivityIndicatorView.Style

    func makeUIView(context _: UIViewRepresentableContext<ActivityIndicator>) -> UIActivityIndicatorView {
        UIActivityIndicatorView(style: style)
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context _: UIViewRepresentableContext<ActivityIndicator>) {
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    }
}
