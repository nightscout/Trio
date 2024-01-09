import SwiftUI
import Swinject

extension IconConfig {
    struct RootView: BaseView {
        @Environment(\.colorScheme) var colorScheme
        var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            IconSelection()
                .onAppear(perform: configureView)
                .scrollContentBackground(.hidden).background(color)
        }
    }
}
