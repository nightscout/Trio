import SwiftUI
import Swinject

extension IconConfig {
    struct RootView: BaseView {
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            IconSelection()
                .onAppear(perform: configureView)
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        }
    }
}
